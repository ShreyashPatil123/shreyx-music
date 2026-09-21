import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/stem.dart';
import 'stream_cache_service.dart';
import 'stream_resolver.dart';
import 'vault_service.dart';

import 'audio_normalization_service.dart';
import 'crossfade_audio_engine.dart';
import 'infinite_radio_service.dart';
import 'equalizer_service.dart';

class ShrexAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer _player = AudioPlayer();
  AudioPlayer? _nextPlayer;
  
  final StreamResolver _resolver = StreamResolver();
  final StreamCacheService _streamCache = StreamCacheService();

  final AudioNormalizationService _normalization = AudioNormalizationService();
  final CrossfadeAudioEngine _crossfade = CrossfadeAudioEngine();
  final InfiniteRadioService _radio = InfiniteRadioService();
  
  AudioNormalizationService get normalization => _normalization;
  CrossfadeAudioEngine get crossfade => _crossfade;
  EqualizerService get equalizer => EqualizerService();

  List<Stem> _queue = [];
  List<Stem> _originalQueue = [];
  int _currentIndex = -1;
  Stem? _activeStem;
  bool _isShuffled = false;
  bool _crossfadeInProgress = false;
  
  List<StreamSubscription> _playerSubscriptions = [];

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
    _attachPlayerListeners(_player);
  }

  void _initAudioStreams() async {
    // Configure music audio session for background and lock screen audio stability
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }
  
  void _attachPlayerListeners(AudioPlayer p) {
    for (var sub in _playerSubscriptions) {
      sub.cancel();
    }
    _playerSubscriptions.clear();

    _playerSubscriptions.add(p.playbackEventStream.listen((PlaybackEvent event) {
      final isPlaying = p.playing;
      final processingState = p.processingState;

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
        updatePosition: p.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
        queueIndex: _currentIndex,
      ));
    }));

    _playerSubscriptions.add(p.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    }));
    
    _playerSubscriptions.add(p.positionStream.listen((position) {
      final dur = p.duration;
      if (dur != null && _crossfade.isEnabled && _crossfade.shouldStartCrossfade(position, dur)) {
        _startCrossfadeToNext();
      }
    }));
  }

  int _currentSessionId = 0;
  
  void _pushMediaItem(Stem targetStem) {
    final mi = MediaItem(
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
    this.mediaItem.add(mi);
  }

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

    _pushMediaItem(stem);

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
            _pushMediaItem(effectiveStem);
            VaultService().updateStem(effectiveStem);
          }

          final Map<String, String>? headers = resolved.userAgent != null
              ? {'User-Agent': resolved.userAgent!}
              : null;
          await _player.setUrl(resolved.uri, headers: headers);

          // ── Step C: Silently cache the stream in background ──
          final cacheId = effectiveStem?.sourceId ?? stem.sourceId;
          if (cacheId.length == 11 && !cacheId.contains(' ')) {
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
      _normalization.applyToPlayer(_player, null);
      VaultService().recordPlay(_activeStem ?? stem);
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

  Future<void> _startCrossfadeToNext() async {
    if (_crossfadeInProgress) return;
    
    final int nextIndex;
    if (_currentIndex + 1 < _queue.length) {
      nextIndex = _currentIndex + 1;
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      nextIndex = 0;
    } else {
      // If we are about to end, let it finish and trigger normal skipToNext/autoplay
      return;
    }
    
    final Stem nextStem = _queue[nextIndex];
    
    _crossfadeInProgress = true;
    _nextPlayer = AudioPlayer();
    
    try {
      final resolved = await _resolver.resolveStream(nextStem);
      final headers = resolved.userAgent != null ? {'User-Agent': resolved.userAgent!} : null;
      await _nextPlayer!.setUrl(resolved.uri, headers: headers);
      
      await _nextPlayer!.setVolume(0.0);
      await _nextPlayer!.play();
      
      final int totalMs = _crossfade.crossfadeDuration.inMilliseconds;
      const int intervalMs = 50;
      int elapsedMs = 0;
      
      Timer.periodic(const Duration(milliseconds: intervalMs), (timer) async {
        elapsedMs += intervalMs;
        if (elapsedMs >= totalMs) {
          timer.cancel();
          
          final oldPlayer = _player;
          _player = _nextPlayer!;
          _nextPlayer = null;
          
          _currentIndex = nextIndex;
          _activeStem = nextStem;
          _activeStemController.add(_activeStem);
          _pushMediaItem(nextStem);
          
          _attachPlayerListeners(_player);
          _normalization.applyToPlayer(_player, null);
          
          await oldPlayer.stop();
          oldPlayer.dispose();
          
          _crossfadeInProgress = false;
          
          _maybeReplenishQueue();
        } else {
           double progress = elapsedMs / totalMs;
           final volumes = _crossfade.calculateVolumes(progress);
           _player.setVolume(volumes.currentVolume);
           _nextPlayer?.setVolume(volumes.nextVolume);
        }
      });
      
    } catch (e) {
      debugPrint('[AudioHandler] Crossfade error: $e');
      _crossfadeInProgress = false;
      _nextPlayer?.dispose();
      _nextPlayer = null;
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
      _maybeReplenishQueue();
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
      await _fetchAndPlayAutoplay();
    }
  }
  
  Future<void> _maybeReplenishQueue() async {
    if (_queue.isNotEmpty && _currentIndex >= _queue.length - 3) {
      final currentStem = _activeStem ?? _queue.last;
      try {
        final tracks = await _radio.fetchRadioTracks(currentStem.sourceId);
        final uniqueTracks = _radio.filterDuplicates(tracks, _queue);
        if (uniqueTracks.isNotEmpty) {
          _queue.addAll(uniqueTracks);
          _queueController.add(_queue);
        }
      } catch (e) {
        debugPrint('[AudioHandler] Background queue replenish error: $e');
      }
    }
  }

  Future<void> _fetchAndPlayAutoplay() async {
    if (_isFetchingAutoplay) return;
    _isFetchingAutoplay = true;

    try {
      final currentStem = _activeStem ?? (_queue.isNotEmpty ? _queue.last : null);
      if (currentStem == null) return;

      debugPrint('[AudioHandler] ⚡ Queue ended. Auto-fetching radio tracks for "${currentStem.title}"...');
      
      final tracks = await _radio.fetchRadioTracks(currentStem.sourceId);
      final uniqueTracks = _radio.filterDuplicates(tracks, _queue);
      
      if (uniqueTracks.isNotEmpty) {
        _queue.addAll(uniqueTracks);
        _queueController.add(_queue);

        if (_currentIndex + 1 < _queue.length) {
          _currentIndex++;
          await playStem(_queue[_currentIndex], preserveQueue: true);
          return;
        }
      }

      // If radio fetch fails/empty, wrap around queue
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

  // ── Android Auto MediaBrowser Support ──

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.browsableRootId || parentMediaId == 'root') {
      return [
        const MediaItem(
          id: 'favorites',
          title: 'Favorites',
          playable: false,
        ),
        const MediaItem(
          id: 'recent',
          title: 'Recently Played',
          playable: false,
        ),
        const MediaItem(
          id: 'playlists',
          title: 'Playlists',
          playable: false,
        ),
      ];
    }
    
    if (parentMediaId == 'favorites') {
      return VaultService().favorites.map(_stemToMediaItem).toList();
    }
    if (parentMediaId == 'recent') {
      return VaultService().getRecentTracks().map(_stemToMediaItem).toList();
    }
    if (parentMediaId == 'playlists') {
      return VaultService().playlists.map((pl) => MediaItem(
        id: 'pl_${pl.id}',
        title: pl.name,
        artist: '${pl.stems.length} tracks',
        artUri: pl.artworkUrl.isNotEmpty ? Uri.tryParse(pl.artworkUrl) : null,
        playable: false,
      )).toList();
    }
    if (parentMediaId.startsWith('pl_')) {
      final realId = parentMediaId.substring(3);
      for (final pl in VaultService().playlists) {
        if (pl.id == realId) {
          return pl.stems.map(_stemToMediaItem).toList();
        }
      }
    }
    return [];
  }

  MediaItem _stemToMediaItem(Stem stem) {
    return MediaItem(
      id: stem.id,
      album: stem.albumName ?? 'ShreyX Music',
      title: stem.title,
      artist: stem.artistName,
      duration: Duration(seconds: stem.durationSec),
      artUri: stem.artworkUrl.isNotEmpty ? Uri.tryParse(stem.artworkUrl) : null,
      playable: true,
      extras: {
        'sourceId': stem.sourceId,
        'durationSec': stem.durationSec,
        'artworkUrl': stem.artworkUrl,
        'albumName': stem.albumName ?? 'ShreyX Music',
        'isLocal': stem.isLocal,
        'localFilePath': stem.localFilePath ?? '',
      },
    );
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    for (final s in VaultService().favorites) {
      if (s.id == mediaId) {
        await playStem(s, queue: VaultService().favorites);
        return;
      }
    }
    for (final pl in VaultService().playlists) {
      for (final s in pl.stems) {
        if (s.id == mediaId) {
          await playStem(s, queue: pl.stems);
          return;
        }
      }
    }
    for (final s in VaultService().getRecentTracks()) {
      if (s.id == mediaId) {
        await playStem(s);
        return;
      }
    }
  }

  void dispose() {
    for (var sub in _playerSubscriptions) {
      sub.cancel();
    }
    _player.dispose();
    _nextPlayer?.dispose();
    _resolver.dispose();
    _normalization.dispose();
    _activeStemController.close();
  }
}
