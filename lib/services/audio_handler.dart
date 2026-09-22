import 'dart:async';
import 'dart:io';
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
  AndroidEqualizer _equalizer = AndroidEqualizer();
  late AudioPlayer _player;
  
  AudioPlayer? _nextPlayer;
  AndroidEqualizer? _nextEqualizer;
  Stem? _preloadedStem;
  bool _isPreloading = false;
  bool _crossfadeInProgress = false;

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
  
  final List<StreamSubscription> _playerSubscriptions = [];

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
    _player = _createAudioPlayer(_equalizer);
    EqualizerService().attachEqualizer(_equalizer);
    _initAudioStreams();
    _attachPlayerListeners(_player);
  }

  AudioPlayer _createAudioPlayer(AndroidEqualizer eq) {
    if (!kIsWeb && Platform.isAndroid) {
      return AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [
            eq,
          ],
        ),
      );
    }
    return AudioPlayer();
  }

  void _initAudioStreams() async {
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
        if (!_crossfadeInProgress) {
          skipToNext();
        }
      }
    }));
    
    _playerSubscriptions.add(p.positionStream.listen((position) {
      final dur = p.duration;
      if (dur == null || !_crossfade.isEnabled) return;

      // 1. Preload next track early (12s before end)
      final remaining = dur - position;
      final preloadThreshold = Duration(seconds: _crossfade.crossfadeSeconds + 8);
      if (remaining <= preloadThreshold && !_isPreloading && _preloadedStem == null && !_crossfadeInProgress) {
        _preloadNextTrack();
      }

      // 2. Trigger crossfade transition when entering crossfade window
      if (_crossfade.shouldStartCrossfade(position, dur) && !_crossfadeInProgress) {
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

    // Invalidate any preloaded next track since user explicitly chose a new track
    _cleanupNextPlayer();

    // 1. Cut off previous audio
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

    // 3. Broadcast buffering state
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
        if (sessionId != _currentSessionId) return;
        await _player.setFilePath(stem.localFilePath!);
      } else {
        // Check LRU disk cache
        final cachedPath = _streamCache.getCachedPath(stem.id);
        if (cachedPath != null) {
          debugPrint('[AudioHandler] ⚡ Cache hit for "${stem.title}"');
          if (sessionId != _currentSessionId) return;
          await _player.setFilePath(cachedPath);
        } else {
          // Resolve stream URL from network
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

          // Silently cache in background
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
      await _player.setVolume(1.0);
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

  int _getNextTrackIndex() {
    if (_currentIndex + 1 < _queue.length) {
      return _currentIndex + 1;
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      return 0;
    }
    return -1;
  }

  Future<void> _preloadNextTrack() async {
    final nextIndex = _getNextTrackIndex();
    if (nextIndex == -1 || nextIndex >= _queue.length) return;

    final stem = _queue[nextIndex];
    _isPreloading = true;
    try {
      debugPrint('[AudioHandler] ⏳ Pre-buffering next track for crossfade: "${stem.title}"');
      final resolved = await _resolver.resolveStream(stem);
      final headers = resolved.userAgent != null ? {'User-Agent': resolved.userAgent!} : null;

      _cleanupNextPlayer();
      _nextEqualizer = AndroidEqualizer();
      _nextPlayer = _createAudioPlayer(_nextEqualizer!);
      await _nextPlayer!.setUrl(resolved.uri, headers: headers);
      await _nextPlayer!.setVolume(0.0);
      _preloadedStem = stem;
      debugPrint('[AudioHandler] ⚡ Pre-buffer ready for crossfade: "${stem.title}"');
    } catch (e) {
      debugPrint('[AudioHandler] Preload next track error: $e');
      _cleanupNextPlayer();
    } finally {
      _isPreloading = false;
    }
  }

  void _cleanupNextPlayer() {
    _nextPlayer?.stop();
    _nextPlayer?.dispose();
    _nextPlayer = null;
    _nextEqualizer = null;
    _preloadedStem = null;
  }

  Future<void> _startCrossfadeToNext() async {
    if (_crossfadeInProgress) return;
    final nextIndex = _getNextTrackIndex();
    if (nextIndex == -1) return;
    final nextStem = _queue[nextIndex];

    _crossfadeInProgress = true;
    try {
      debugPrint('[AudioHandler] 🔀 Starting seamless crossfade into "${nextStem.title}" (${_crossfade.crossfadeSeconds}s)');
      
      // If next player is not preloaded yet, prepare it now
      if (_nextPlayer == null || _preloadedStem?.id != nextStem.id) {
        _cleanupNextPlayer();
        _nextEqualizer = AndroidEqualizer();
        _nextPlayer = _createAudioPlayer(_nextEqualizer!);
        final resolved = await _resolver.resolveStream(nextStem);
        final headers = resolved.userAgent != null ? {'User-Agent': resolved.userAgent!} : null;
        await _nextPlayer!.setUrl(resolved.uri, headers: headers);
        await _nextPlayer!.setVolume(0.0);
      }

      final targetPlayer = _nextPlayer!;
      final targetEqualizer = _nextEqualizer!;
      final oldPlayer = _player;

      // Start playing the incoming track at 0 volume
      await targetPlayer.play();

      final int totalMs = _crossfade.crossfadeDuration.inMilliseconds;
      const int intervalMs = 40;
      int elapsedMs = 0;

      Timer.periodic(const Duration(milliseconds: intervalMs), (timer) async {
        elapsedMs += intervalMs;
        if (elapsedMs >= totalMs) {
          timer.cancel();

          // Swap active player reference
          _player = targetPlayer;
          _equalizer = targetEqualizer;
          EqualizerService().attachEqualizer(_equalizer);

          _nextPlayer = null;
          _nextEqualizer = null;
          _preloadedStem = null;

          _currentIndex = nextIndex;
          _activeStem = nextStem;
          _activeStemController.add(_activeStem);
          _pushMediaItem(nextStem);

          _attachPlayerListeners(_player);
          _normalization.applyToPlayer(_player, null);
          VaultService().recordPlay(nextStem);

          await oldPlayer.stop();
          oldPlayer.dispose();

          _crossfadeInProgress = false;
          debugPrint('[AudioHandler] 🔀 Crossfade complete. Now playing "${nextStem.title}"');

          _maybeReplenishQueue();
        } else {
          final double progress = elapsedMs / totalMs;
          final volumes = _crossfade.calculateVolumes(progress);
          oldPlayer.setVolume(volumes.currentVolume);
          targetPlayer.setVolume(volumes.nextVolume);
        }
      });
    } catch (e) {
      debugPrint('[AudioHandler] Crossfade execution error: $e');
      _crossfadeInProgress = false;
      _cleanupNextPlayer();
      // Fallback: normal skip
      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        await playStem(_queue[_currentIndex], preserveQueue: true);
      }
    }
  }

  @override
  Future<void> play() async {
    if (_player.audioSource == null) return;
    try {
      if (_player.volume <= 0.05) {
        await _player.setVolume(1.0);
      }
      await _player.play();
    } catch (e) {
      debugPrint('[AudioHandler] play error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('[AudioHandler] pause error: $e');
    }
  }

  @override
  Future<void> stop() async {
    _cleanupNextPlayer();
    try {
      await _player.stop();
    } catch (_) {}
    _activeStem = null;
    _activeStemController.add(null);
    mediaItem.add(null);
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_player.audioSource == null) return;
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('[AudioHandler] seek error: $e');
    }
  }

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

    // Smooth 150ms fade-out on manual skip if playing
    if (_crossfade.isEnabled && _player.playing) {
      try {
        final double curVol = _player.volume;
        for (int i = 3; i >= 0; i--) {
          await _player.setVolume(curVol * (i / 3.0));
          await Future.delayed(const Duration(milliseconds: 25));
        }
      } catch (_) {}
    }

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
      // Autonomous infinite radio when queue ends
      await _fetchAndPlayAutoplay();
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

  void setQueue(List<Stem> newQueue) {
    if (newQueue.isEmpty) return;
    _queue = List.from(newQueue);
    _originalQueue = List.from(newQueue);
    if (_activeStem != null) {
      final idx = _queue.indexWhere((s) => s.id == _activeStem!.id);
      _currentIndex = idx != -1 ? idx : 0;
    } else {
      _currentIndex = 0;
    }
    _queueController.add(_queue);
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
    _queueController.add(_queue);
  }

  void playNext(Stem stem) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, stem);
    } else {
      _queue.add(stem);
    }
    _queueController.add(_queue);
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
    _cleanupNextPlayer();
    _player.dispose();
    _resolver.dispose();
    _normalization.dispose();
    _activeStemController.close();
  }
}
