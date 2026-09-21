import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';
import 'stream_cache_service.dart';
import 'stream_resolver.dart';
import 'vault_service.dart';

class ShrexAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final StreamResolver _resolver = StreamResolver();
  final StreamCacheService _streamCache = StreamCacheService();

  List<Stem> _queue = [];
  List<Stem> _originalQueue = [];
  int _currentIndex = -1;
  Stem? _activeStem;
  bool _isShuffled = false;

  Stem? get activeStem => _activeStem;
  List<Stem> get currentQueue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isShuffled => _isShuffled;
  AudioPlayer get player => _player;

  final _activeStemController = BehaviorSubject<Stem?>();
  Stream<Stem?> get activeStemStream => _activeStemController.stream;

  final _queueController = BehaviorSubject<List<Stem>>.seeded([]);
  Stream<List<Stem>> get queueStream => _queueController.stream;

  ShrexAudioHandler() {
    _initAudioStreams();
  }

  void _initAudioStreams() async {
    // Configure music audio session for background and lock screen audio stability
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    // Broadcast playback events to system notification & lock screen
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final isPlaying = _player.playing;
      final processingState = _player.processingState;

      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[processingState]!,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ));
    });

    // Auto-advance to next track on completion
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  int _currentSessionId = 0;

  Future<void> playStem(Stem stem, {List<Stem>? queue, bool preserveQueue = false}) async {
    final int sessionId = ++_currentSessionId;

    // 1. Immediately cut off any previous audio (instant 0ms stop)
    try {
      await _player.stop();
    } catch (_) {}

    // 2. Set queue
    if (queue != null && queue.isNotEmpty) {
      _originalQueue = List.from(queue);
      if (_isShuffled) {
        final rest = queue.where((s) => s.id != stem.id).toList()..shuffle();
        _queue = [stem, ...rest];
        _currentIndex = 0;
      } else {
        _queue = List.from(queue);
        _currentIndex = _queue.indexWhere((s) => s.id == stem.id);
        if (_currentIndex == -1) {
          _queue.insert(0, stem);
          _currentIndex = 0;
        }
      }
      _queueController.add(_queue);
    } else if (!preserveQueue) {
      if (_queue.isEmpty || !_queue.any((s) => s.id == stem.id)) {
        _queue = [stem];
        _originalQueue = [stem];
        _currentIndex = 0;
      } else {
        _currentIndex = _queue.indexWhere((s) => s.id == stem.id);
      }
      _queueController.add(_queue);
    }

    _activeStem = stem;
    _activeStemController.add(stem);

    // 3. Immediately broadcast buffering state so play button shows loading
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.buffering,
      playing: true,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));

    void pushMediaItem(Stem targetStem) {
      final mediaItem = MediaItem(
        id: targetStem.id,
        album: targetStem.albumName ?? 'ShreyX Music',
        title: targetStem.title,
        artist: targetStem.artistName,
        duration: Duration(seconds: targetStem.durationSec),
        artUri: targetStem.artworkUrl.isNotEmpty ? Uri.tryParse(targetStem.artworkUrl) : null,
        extras: {
          'sourceId': targetStem.sourceId,
          'durationSec': targetStem.durationSec,
          'artworkUrl': targetStem.artworkUrl,
          'albumName': targetStem.albumName ?? 'ShreyX Music',
          'isLocal': targetStem.isLocal,
          'localFilePath': targetStem.localFilePath ?? '',
        },
      );
      this.mediaItem.add(mediaItem);
    }

    pushMediaItem(stem);

    try {
      if (stem.isLocal && stem.localFilePath != null) {
        // ── Already a user-downloaded local file ──
        if (sessionId != _currentSessionId) return;
        await _player.setFilePath(stem.localFilePath!);
      } else {
        // ── Step A: Check LRU disk cache (instant 0ms) ──
        final cachedPath = _streamCache.getCachedPath(stem.id);
        if (cachedPath != null) {
          debugPrint('[AudioHandler] ⚡ cache hit for "${stem.title}"');
          if (sessionId != _currentSessionId) return;
          await _player.setFilePath(cachedPath);
        } else {
          // ── Step B: Resolve stream URL from network ──
          final resolved = await _resolver.resolveStream(stem);
          if (sessionId != _currentSessionId) return;

          Stem? effectiveStem = resolved.effectiveStem;
          if (effectiveStem != null) {
            _activeStem = effectiveStem;
            _activeStemController.add(_activeStem);
            pushMediaItem(effectiveStem);
            VaultService().updateStem(effectiveStem);
          }

          final Map<String, String>? headers = resolved.userAgent != null
              ? {'User-Agent': resolved.userAgent!}
              : null;
          await _player.setUrl(resolved.uri, headers: headers);

          // ── Step C: Silently cache the stream in background ──
          // Use the resolved YouTube video ID as the cache key
          final cacheId = effectiveStem?.sourceId ?? stem.sourceId;
          // Only cache if we have an 11-char video ID (means we know
          // the source and can reliably re-key it)
          if (cacheId.length == 11 && !cacheId.contains(' ')) {
            // Fire-and-forget — never blocks playback
            _streamCache.backgroundCacheStream(
              stemId: stem.id,
              url: resolved.uri,
              userAgent: resolved.userAgent,
            );
          }
        }
      }

      if (sessionId != _currentSessionId) return;
      await _player.play();
    } catch (e) {
      debugPrint('[AudioHandler] playStem error: $e');
      if (sessionId == _currentSessionId) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
      }
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _activeStem = null;
    _activeStemController.add(null);
    mediaItem.add(null);
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> seekBy(Duration offset) async {
    final newPos = _player.position + offset;
    final duration = _player.duration ?? Duration(seconds: _activeStem?.durationSec ?? 0);
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > duration ? duration : newPos);
    await seek(clamped);
  }

  @override
  Future<void> fastForward() => seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() => seekBy(const Duration(seconds: -10));

  @override
  Future<void> seekForward(bool begin) async {
    if (begin) {
      await seekBy(const Duration(seconds: 10));
    }
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) {
      await seekBy(const Duration(seconds: -10));
    }
  }

  bool _isFetchingAutoplay = false;

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty && _activeStem == null) return;

    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await playStem(_queue[_currentIndex], preserveQueue: true);
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      if (_isShuffled && _queue.length > 1) {
        final current = _queue[_currentIndex];
        final rest = _queue.where((s) => s.id != current.id).toList()..shuffle();
        _queue = [current, ...rest];
        _queueController.add(_queue);
      }
      _currentIndex = 0;
      await playStem(_queue[0], preserveQueue: true);
    } else {
      // ── AUTONOMOUS INFINITE RADIO / RELATED AUTOPLAY ──
      // When reaching end of queue or playing a standalone track,
      // dynamically fetch related YouTube tracks so playback NEVER stops!
      await _fetchAndPlayAutoplay();
    }
  }

  Future<void> _fetchAndPlayAutoplay() async {
    if (_isFetchingAutoplay) return;
    _isFetchingAutoplay = true;

    try {
      final currentStem = _activeStem ?? (_queue.isNotEmpty ? _queue.last : null);
      if (currentStem == null) return;

      debugPrint('[AudioHandler] ⚡ Queue ended. Auto-fetching related songs for "${currentStem.title}"...');
      final yt = YoutubeExplode();
      try {
        List<Stem> nextStems = [];

        // Method 1: Try getRelatedVideos via Video instance
        try {
          if (currentStem.sourceId.length == 11 && !currentStem.sourceId.contains(' ')) {
            final videoObj = await yt.videos.get(currentStem.sourceId).timeout(const Duration(seconds: 3));
            final related = await yt.videos.getRelatedVideos(videoObj).timeout(const Duration(seconds: 3));
            if (related != null && related.isNotEmpty) {
              for (final v in related.where((x) => x.id.value != currentStem.sourceId).take(5)) {
                final art = v.thumbnails.highResUrl.isNotEmpty
                    ? v.thumbnails.highResUrl
                    : v.thumbnails.standardResUrl;
                nextStems.add(Stem(
                  id: 'yt_${v.id.value}',
                  title: v.title,
                  artistName: v.author,
                  artworkUrl: art,
                  durationSec: v.duration?.inSeconds ?? 0,
                  sourceId: v.id.value,
                ));
              }
            }
          }
        } catch (_) {}

        // Method 2: Fallback search if related was empty
        if (nextStems.isEmpty) {
          final query = '${currentStem.artistName} songs official audio';
          final searchHits = await yt.search.search(query).timeout(const Duration(seconds: 3));
          for (final v in searchHits.where((x) => x.id.value != currentStem.sourceId).take(5)) {
            final art = v.thumbnails.highResUrl.isNotEmpty
                ? v.thumbnails.highResUrl
                : v.thumbnails.standardResUrl;
            nextStems.add(Stem(
              id: 'yt_${v.id.value}',
              title: v.title,
              artistName: v.author,
              artworkUrl: art,
              durationSec: v.duration?.inSeconds ?? 0,
              sourceId: v.id.value,
            ));
          }
        }

        if (nextStems.isNotEmpty) {
          _queue.addAll(nextStems);
          _queueController.add(_queue);

          if (_currentIndex + 1 < _queue.length) {
            _currentIndex++;
            await playStem(_queue[_currentIndex], preserveQueue: true);
            return;
          }
        }
      } finally {
        yt.close();
      }

      // If related search fails, wrap around queue
      if (_queue.isNotEmpty) {
        _currentIndex = 0;
        await playStem(_queue[0], preserveQueue: true);
      }
    } catch (e) {
      debugPrint('[AudioHandler] Autoplay error: $e');
      if (_queue.isNotEmpty) {
        _currentIndex = 0;
        await playStem(_queue[0], preserveQueue: true);
      }
    } finally {
      _isFetchingAutoplay = false;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_queue.isEmpty) return;
    if (_currentIndex - 1 >= 0) {
      _currentIndex--;
      await playStem(_queue[_currentIndex], preserveQueue: true);
    } else {
      await seek(Duration.zero);
    }
  }

  void setShuffled(bool enabled, {List<Stem>? originalQueue}) {
    if (originalQueue != null && originalQueue.isNotEmpty) {
      _originalQueue = List.from(originalQueue);
    } else if (_originalQueue.isEmpty && _queue.isNotEmpty) {
      _originalQueue = List.from(_queue);
    }

    _isShuffled = enabled;
    if (enabled) {
      if (_queue.length <= 1) return;
      final current = _activeStem;
      final rest = _queue.where((s) => s.id != current?.id).toList()..shuffle();
      if (current != null) {
        _queue = [current, ...rest];
        _currentIndex = 0;
      } else {
        _queue = rest;
        _currentIndex = 0;
      }
    } else {
      // Restore original queue order
      if (_originalQueue.isNotEmpty) {
        _queue = List.from(_originalQueue);
        if (_activeStem != null) {
          final idx = _queue.indexWhere((s) => s.id == _activeStem!.id);
          _currentIndex = idx != -1 ? idx : 0;
        } else {
          _currentIndex = 0;
        }
      }
    }
  }

  void shuffleQueue() {
    setShuffled(true);
  }

  void addToQueue(Stem stem) {
    _queue.add(stem);
  }

  void playNext(Stem stem) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, stem);
    } else {
      _queue.add(stem);
    }
  }

  void setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
  }

  void dispose() {
    _player.dispose();
    _resolver.dispose();
    _activeStemController.close();
  }
}
