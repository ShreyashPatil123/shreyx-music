import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/stem.dart';
import 'audio_normalization_service.dart';
import 'crossfade_audio_engine.dart';
import 'equalizer_service.dart';
import 'infinite_radio_service.dart';
import 'playback_diagnostics_service.dart';
import 'playback_event_pipeline.dart';
import 'playback_queue_controller.dart';
import 'stream_cache_service.dart';
import 'track_preparation_service.dart';
import 'vault_service.dart';

class ShrexAudioHandler extends BaseAudioHandler with SeekHandler {
  AndroidEqualizer _equalizer = AndroidEqualizer();
  late AudioPlayer _player;

  AudioPlayer? _nextPlayer;
  AndroidEqualizer? _nextEqualizer;
  Stem? _preloadedStem;
  bool _isPreloading = false;
  bool _crossfadeInProgress = false;

  final TrackPreparationService _preparation = TrackPreparationService();
  final StreamCacheService _streamCache = StreamCacheService();
  final AudioNormalizationService _normalization = AudioNormalizationService();
  final CrossfadeAudioEngine _crossfade = CrossfadeAudioEngine();
  final InfiniteRadioService _radio = InfiniteRadioService();
  final PlaybackDiagnosticsService _diagnostics = PlaybackDiagnosticsService();
  final PlaybackQueueController _queueController = PlaybackQueueController();

  AudioNormalizationService get normalization => _normalization;
  CrossfadeAudioEngine get crossfade => _crossfade;
  EqualizerService get equalizer => EqualizerService();
  PlaybackQueueController get queueController => _queueController;

  final List<StreamSubscription> _playerSubscriptions = [];

  Stem? _activeStem;
  Stem? get activeStem => _activeStem;
  List<Stem> get currentQueue => _queueController.stems;
  int get currentIndex => _queueController.currentIndex;
  bool get isShuffled => _queueController.isShuffled;
  AudioPlayer get player => _player;

  final _activeStemController = BehaviorSubject<Stem?>();
  Stream<Stem?> get activeStemStream => _activeStemController.stream;
  Stream<List<Stem>> get queueStream => _queueController.queueStream.map((items) => items.map((i) => i.stem).toList());

  int _currentSessionId = 0;
  Timer? _bgCacheTimer;

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
          androidAudioEffects: [eq],
        ),
      );
    }
    return AudioPlayer();
  }

  void _initAudioStreams() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // Audio interruption handling (e.g. phone calls, alarms)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(_player.volume * 0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // Headphone unplug handling
      session.becomingNoisyEventStream.listen((_) {
        pause();
      });
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
        queueIndex: _queueController.currentIndex,
      ));

      if (processingState == ProcessingState.ready) {
        final currentDiag = _diagnostics.currentSession;
        if (currentDiag != null) {
          _diagnostics.markPlayerReady(currentDiag.sessionId);
        }
      }
    }));

    _playerSubscriptions.add(p.playerStateStream.listen((state) {
      if (state.playing && state.processingState == ProcessingState.ready) {
        final currentDiag = _diagnostics.currentSession;
        if (currentDiag != null) {
          _diagnostics.markFirstAudioPlayed(currentDiag.sessionId);
        }
      }

      if (state.processingState == ProcessingState.completed) {
        if (!_crossfadeInProgress) {
          skipToNext();
        }
      }
    }));

    _playerSubscriptions.add(p.positionStream.listen((position) {
      final dur = p.duration;
      if (dur == null) return;

      // Stable playback reached: schedule background cache with priority (Point 9)
      if (position.inSeconds >= 5 && _bgCacheTimer == null && _activeStem != null) {
        _scheduleBackgroundCache(_activeStem!);
      }

      if (!_crossfade.isEnabled) return;

      // Preload next track early (12s before end)
      final remaining = dur - position;
      final preloadThreshold = Duration(seconds: _crossfade.crossfadeSeconds + 8);
      if (remaining <= preloadThreshold && !_isPreloading && _preloadedStem == null && !_crossfadeInProgress) {
        _preloadNextTrack();
      }

      // Trigger crossfade transition when entering crossfade window
      if (_crossfade.shouldStartCrossfade(position, dur) && !_crossfadeInProgress) {
        _startCrossfadeToNext();
      }
    }));
  }

  void _scheduleBackgroundCache(Stem stem) {
    _bgCacheTimer?.cancel();
    _bgCacheTimer = Timer(const Duration(seconds: 2), () async {
      // Only cache if player is currently playing smoothly and not buffering
      if (_player.playing && _player.processingState == ProcessingState.ready) {
        final cached = _preparation.cache.get(stem.sourceId);
        if (cached != null) {
          await _streamCache.backgroundCacheStream(
            stemId: stem.id,
            url: cached.uri,
            userAgent: cached.userAgent,
            container: cached.container,
          );
        }
      }
    });
  }

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
    mediaItem.add(mi);
  }

  /// Initiates playback for [stem] with optional [queue].
  ///
  /// Updates player state immediately to prevent frozen UI, enforces controlled
  /// fallback resolution, and implements non-blocking failure recovery.
  Future<void> playStem(Stem stem, {List<Stem>? queue, bool preserveQueue = false}) async {
    final int sessionId = ++_currentSessionId;
    _bgCacheTimer?.cancel();
    _bgCacheTimer = null;

    // Start diagnostics session
    final diag = _diagnostics.startSession(
      stemId: stem.id,
      title: stem.title,
      artist: stem.artistName,
      sourceId: stem.sourceId,
    );

    _cleanupNextPlayer();

    // 1. Immediately update global player UI to show song metadata and buffering
    _activeStem = stem;
    _activeStemController.add(stem);
    _pushMediaItem(stem);

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
      queueIndex: _queueController.currentIndex,
    ));

    // 2. Queue management via PlaybackQueueController
    if (queue != null && queue.isNotEmpty) {
      _queueController.setQueue(queue, initialStem: stem);
    } else if (!preserveQueue) {
      if (_queueController.stems.isEmpty || !_queueController.stems.any((s) => s.id == stem.id)) {
        _queueController.setQueue([stem], initialStem: stem);
      }
    }

    _queueController.updateActiveTrackState(TrackPlaybackState.preparing);

    // 3. Resolve and prepare stream
    try {
      if (stem.isLocal && stem.localFilePath != null) {
        if (sessionId != _currentSessionId) return;
        await _player.stop();
        await _player.setFilePath(stem.localFilePath!);
      } else {
        // Check disk LRU cache first
        final cachedPath = _streamCache.getCachedPath(stem.id);
        if (cachedPath != null) {
          debugPrint('[AudioHandler] ⚡ Disk cache hit for "${stem.title}"');
          if (sessionId != _currentSessionId) return;
          _diagnostics.markStreamSelected(diag.sessionId, resolver: 'disk_cache', wasCached: true);
          await _player.stop();
          await _player.setFilePath(cachedPath);
        } else {
          // Resolve stream URL using TrackPreparationService with controlled fallback
          final prepared = await _preparation.prepareTrack(
            stem,
            diagnosticsSessionId: diag.sessionId,
          );

          if (sessionId != _currentSessionId) return;

          Stem? effectiveStem = prepared.effectiveStem;
          if (effectiveStem != null) {
            _activeStem = effectiveStem;
            _activeStemController.add(_activeStem);
            _pushMediaItem(effectiveStem);
            VaultService().updateStem(effectiveStem);
          }

          final headers = prepared.userAgent != null ? {'User-Agent': prepared.userAgent!} : null;

          _diagnostics.markPlayerSetUrlStart(diag.sessionId);
          await _player.stop();
          await _player.setUrl(prepared.uri, headers: headers);
        }
      }

      if (sessionId != _currentSessionId) return;

      _queueController.updateActiveTrackState(TrackPlaybackState.playing);
      await _player.setVolume(1.0);
      await _player.play();
      _normalization.applyToPlayer(_player, null);
      VaultService().recordPlay(_activeStem ?? stem);
      PlaybackEventPipeline().onPlayStarted(_activeStem ?? stem, sessionId: diag.sessionId);
    } catch (e) {
      debugPrint('[AudioHandler] Playback error on "${stem.title}": $e');

      // Purge invalid/403 stream from cache immediately (Safeguard 2)
      _preparation.invalidateStream(stem.sourceId);
      _diagnostics.markError(diag.sessionId, reason: e.toString());

      if (sessionId != _currentSessionId) return;

      // Non-blocking failure recovery (Point 13 & Safeguard 3):
      // Mark current track failed, keep queue intact, and advance to next track
      final nextItem = _queueController.handleCurrentTrackFailure(e.toString());
      if (nextItem != null) {
        debugPrint('[AudioHandler] ⏭️ Auto-recovering: Advancing to "${nextItem.stem.title}"');
        await playStem(nextItem.stem, preserveQueue: true);
      } else {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
      }
    }
  }

  int _getNextTrackIndex() => _queueController.getNextIndex();

  Future<void> _preloadNextTrack() async {
    final nextIdx = _getNextTrackIndex();
    if (nextIdx == -1 || nextIdx >= _queueController.stems.length) return;

    final stem = _queueController.stems[nextIdx];
    _isPreloading = true;
    try {
      debugPrint('[AudioHandler] ⏳ Pre-buffering next track for crossfade: "${stem.title}"');
      final prepared = await _preparation.prepareTrack(stem);
      final headers = prepared.userAgent != null ? {'User-Agent': prepared.userAgent!} : null;

      _cleanupNextPlayer();
      _nextEqualizer = AndroidEqualizer();
      _nextPlayer = _createAudioPlayer(_nextEqualizer!);
      await _nextPlayer!.setUrl(prepared.uri, headers: headers);
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
    try {
      _nextPlayer?.stop();
      _nextPlayer?.dispose();
    } catch (_) {}
    _nextPlayer = null;
    _nextEqualizer = null;
    _preloadedStem = null;
  }

  Future<void> _startCrossfadeToNext() async {
    if (_crossfadeInProgress) return;
    final nextIdx = _getNextTrackIndex();
    if (nextIdx == -1 || nextIdx >= _queueController.stems.length) return;
    final nextStem = _queueController.stems[nextIdx];

    _crossfadeInProgress = true;
    try {
      if (_nextPlayer == null || _preloadedStem?.id != nextStem.id) {
        _cleanupNextPlayer();
        _nextEqualizer = AndroidEqualizer();
        _nextPlayer = _createAudioPlayer(_nextEqualizer!);
        final prepared = await _preparation.prepareTrack(nextStem);
        final headers = prepared.userAgent != null ? {'User-Agent': prepared.userAgent!} : null;
        await _nextPlayer!.setUrl(prepared.uri, headers: headers);
        await _nextPlayer!.setVolume(0.0);
      }

      final targetPlayer = _nextPlayer!;
      final targetEqualizer = _nextEqualizer!;
      final oldPlayer = _player;

      await targetPlayer.play();

      final int totalMs = _crossfade.crossfadeDuration.inMilliseconds;
      const int intervalMs = 40;
      int elapsedMs = 0;

      Timer.periodic(const Duration(milliseconds: intervalMs), (timer) async {
        elapsedMs += intervalMs;
        if (elapsedMs >= totalMs) {
          timer.cancel();

          _player = targetPlayer;
          _equalizer = targetEqualizer;
          EqualizerService().attachEqualizer(_equalizer);

          _nextPlayer = null;
          _nextEqualizer = null;
          _preloadedStem = null;

          _queueController.advanceToNext();
          _activeStem = nextStem;
          _activeStemController.add(_activeStem);
          _pushMediaItem(nextStem);

          _attachPlayerListeners(_player);
          _normalization.applyToPlayer(_player, null);
          VaultService().recordPlay(nextStem);

          try {
            await oldPlayer.stop();
            oldPlayer.dispose();
          } catch (_) {}

          _crossfadeInProgress = false;
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
      // Clean fallback: standard skip
      skipToNext();
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
    _bgCacheTimer?.cancel();
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
    final clamped = newPos < Duration.zero ? Duration.zero : (newPos > duration ? duration : newPos);
    await seek(clamped);
  }

  @override
  Future<void> fastForward() => seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() => seekBy(const Duration(seconds: -10));

  @override
  Future<void> seekForward(bool begin) async {
    if (begin) await seekBy(const Duration(seconds: 10));
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) await seekBy(const Duration(seconds: -10));
  }

  bool _isFetchingAutoplay = false;

  @override
  Future<void> skipToNext() async {
    if (_queueController.stems.isEmpty && _activeStem == null) return;

    final nextItem = _queueController.advanceToNext();
    if (nextItem != null) {
      await playStem(nextItem.stem, preserveQueue: true);
      _maybeReplenishQueue();
    } else {
      // Queue exhausted: Fetch infinite radio recommendations (Point 16)
      await _fetchAndPlayAutoplay();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    final prevItem = _queueController.retreatToPrevious();
    if (prevItem != null) {
      await playStem(prevItem.stem, preserveQueue: true);
    } else {
      await seek(Duration.zero);
    }
  }

  void setQueue(List<Stem> newQueue) {
    _queueController.setQueue(newQueue, initialStem: _activeStem);
  }

  Future<void> _maybeReplenishQueue() async {
    if (_queueController.stems.isNotEmpty && _queueController.currentIndex >= _queueController.stems.length - 3) {
      final currentStem = _activeStem ?? _queueController.stems.last;
      try {
        final tracks = await _radio.fetchRadioTracks(currentStem.sourceId);
        final uniqueTracks = _radio.filterDuplicates(tracks, _queueController.stems);
        if (uniqueTracks.isNotEmpty) {
          _queueController.appendUniqueTracks(uniqueTracks);
        }
      } catch (e) {
        debugPrint('[AudioHandler] Background queue replenish error: $e');
      }
    }
  }

  /// Autoplay / Infinite Radio at queue end (Point 16):
  /// Fetches new candidates. If empty/unavailable, cleanly stops without restarting at index 0.
  Future<void> _fetchAndPlayAutoplay() async {
    if (_isFetchingAutoplay) return;
    _isFetchingAutoplay = true;

    try {
      final currentStem = _activeStem ?? (_queueController.stems.isNotEmpty ? _queueController.stems.last : null);
      if (currentStem == null) return;

      debugPrint('[AudioHandler] ⚡ Queue ended. Auto-fetching radio tracks for "${currentStem.title}"...');
      final tracks = await _radio.fetchRadioTracks(currentStem.sourceId);
      final uniqueTracks = _radio.filterDuplicates(tracks, _queueController.stems);

      if (uniqueTracks.isNotEmpty) {
        _queueController.appendUniqueTracks(uniqueTracks);
        final nextItem = _queueController.advanceToNext();
        if (nextItem != null) {
          await playStem(nextItem.stem, preserveQueue: true);
          return;
        }
      }

      // If loopMode is ALL, explicit user request to repeat playlist
      if (_player.loopMode == LoopMode.all && _queueController.stems.isNotEmpty) {
        _queueController.setQueue(_queueController.stems, initialIndex: 0);
        await playStem(_queueController.stems[0], preserveQueue: true);
      } else {
        // Stop cleanly - do NOT loop to 0 (Point 16)
        debugPrint('[AudioHandler] 🏁 End of queue reached. No more playable radio tracks.');
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
          playing: false,
        ));
      }
    } catch (e) {
      debugPrint('[AudioHandler] Autoplay error: $e');
    } finally {
      _isFetchingAutoplay = false;
    }
  }

  void setShuffled(bool enabled, {List<Stem>? originalQueue}) {
    _queueController.setShuffled(enabled);
  }

  void shuffleQueue() {
    setShuffled(true);
  }

  void addToQueue(Stem stem) {
    _queueController.addToQueue(stem);
  }

  void playNext(Stem stem) {
    _queueController.playNext(stem);
  }

  void setLoopMode(LoopMode mode) {
    _player.setLoopMode(mode);
    _queueController.setLoopMode(mode);
  }

  // ── Android Auto MediaBrowser Support ──

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    if (parentMediaId == AudioService.browsableRootId || parentMediaId == 'root') {
      return [
        const MediaItem(id: 'favorites', title: 'Favorites', playable: false),
        const MediaItem(id: 'recent', title: 'Recently Played', playable: false),
        const MediaItem(id: 'playlists', title: 'Playlists', playable: false),
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
    _bgCacheTimer?.cancel();
    _player.dispose();
    _preparation.dispose();
    _normalization.dispose();
    _activeStemController.close();
    _queueController.dispose();
  }
}
