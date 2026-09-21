import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/lyric_line.dart';
import '../models/stem.dart';
import '../services/audio_handler.dart';
import '../services/infinite_radio_service.dart';
import '../services/lyrics_service.dart';

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ShrexAudioHandler _audioHandler;

  Stem? _activeStem;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  LoopMode _loopMode = LoopMode.off;
  bool _isShuffled = false;

  ParsedLyrics? _lyrics;
  bool _isLoadingLyrics = false;
  int _activeLyricIndex = -1;
  bool _isLoadingRadio = false;

  StreamSubscription? _activeStemSub;
  StreamSubscription? _playbackStateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _queueSub;

  Stem? get activeStem => _activeStem;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;
  LoopMode get loopMode => _loopMode;
  bool get isShuffled => _isShuffled;
  List<Stem> get queue => _audioHandler.currentQueue;
  int get currentIndex => _audioHandler.currentIndex;
  List<Stem> get upNextQueue {
    final q = _audioHandler.currentQueue;
    final idx = _audioHandler.currentIndex;
    if (idx >= 0 && idx + 1 < q.length) {
      return q.sublist(idx + 1);
    }
    return [];
  }

  ParsedLyrics? get lyrics => _lyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  int get activeLyricIndex => _activeLyricIndex;
  bool get isLoadingRadio => _isLoadingRadio;

  PlayerProvider(this._audioHandler) {
    WidgetsBinding.instance.addObserver(this);
    _syncInitialState();
    _initSubscriptions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncInitialState();
      notifyListeners();
    }
  }

  void _syncInitialState() {
    if (_audioHandler.activeStem != null) {
      _activeStem = _audioHandler.activeStem;
    } else if (_audioHandler.mediaItem.value != null) {
      final item = _audioHandler.mediaItem.value!;
      final extras = item.extras;
      final bool isLocal = extras != null && extras['isLocal'] == true;
      final String? localPath = isLocal ? extras['localFilePath']?.toString() : null;
      _activeStem = Stem(
        id: item.id,
        sourceId: extras?['sourceId']?.toString() ?? item.id,
        title: item.title,
        artistName: item.artist ?? 'Unknown Artist',
        albumName: item.album,
        artworkUrl: item.artUri?.toString() ?? '',
        durationSec: item.duration?.inSeconds ?? 0,
        localFilePath: localPath,
      );
    }

    _isPlaying = _audioHandler.player.playing;
    _position = _audioHandler.player.position;
    if (_audioHandler.player.duration != null && _audioHandler.player.duration! > Duration.zero) {
      _duration = _audioHandler.player.duration!;
    } else if (_activeStem != null && _activeStem!.durationSec > 0) {
      _duration = Duration(seconds: _activeStem!.durationSec);
    }

    if (_activeStem != null) {
      _fetchLyrics(_activeStem!);
    }
  }

  void _initSubscriptions() {
    _audioHandler.mediaItem.listen((item) {
      if (item != null && (_activeStem == null || _activeStem!.id != item.id)) {
        final extras = item.extras;
        final bool isLocal = extras != null && extras['isLocal'] == true;
        final String? localPath = isLocal ? extras['localFilePath']?.toString() : null;
        _activeStem = Stem(
          id: item.id,
          sourceId: extras?['sourceId']?.toString() ?? item.id,
          title: item.title,
          artistName: item.artist ?? 'Unknown Artist',
          albumName: item.album,
          artworkUrl: item.artUri?.toString() ?? '',
          durationSec: item.duration?.inSeconds ?? 0,
          localFilePath: localPath,
        );
        _duration = Duration(seconds: _activeStem!.durationSec);
        _fetchLyrics(_activeStem!);
        notifyListeners();
      }
    });

    _activeStemSub = _audioHandler.activeStemStream.listen((stem) {
      if (stem != null) {
        _activeStem = stem;
        _duration = Duration(seconds: stem.durationSec);
        _fetchLyrics(stem);
        notifyListeners();
      }
    });

    _playbackStateSub = _audioHandler.playbackState.listen((state) {
      _isPlaying = state.playing;
      _isBuffering = state.processingState == AudioProcessingState.buffering ||
          state.processingState == AudioProcessingState.loading;
      notifyListeners();
    });

    _posSub = _audioHandler.player.positionStream.listen((pos) {
      _position = pos;
      _updateActiveLyricIndex();
      notifyListeners();
    });

    _durSub = _audioHandler.player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _duration = dur;
        notifyListeners();
      }
    });

    _queueSub = _audioHandler.queueStream.listen((_) {
      notifyListeners();
    });
  }

  Future<void> playStem(Stem stem, {List<Stem>? queue}) async {
    _position = Duration.zero;
    _duration = Duration(seconds: stem.durationSec);
    _isBuffering = true;
    _activeStem = stem;
    notifyListeners();
    try {
      await _audioHandler.playStem(stem, queue: queue);
    } catch (e) {
      debugPrint('[PlayerProvider] playStem error: $e');
      _isBuffering = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Plays a single song immediately and generates a queue of relatable songs
  /// tailored specifically to this song using Infinite Radio.
  Future<void> playWithRadio(Stem stem) async {
    _position = Duration.zero;
    _duration = Duration(seconds: stem.durationSec);
    _isBuffering = true;
    _activeStem = stem;
    _isLoadingRadio = true;
    notifyListeners();

    try {
      // 1. Play selected song immediately with only itself in the queue
      await _audioHandler.playStem(stem, queue: [stem]);

      // 2. Fetch relatable songs for this track via InfiniteRadioService
      debugPrint('[PlayerProvider] Fetching relatable songs for "${stem.title}" (${stem.sourceId})...');
      final radioTracks = await InfiniteRadioService().fetchRadioTracks(stem.sourceId, count: 20);

      if (radioTracks.isNotEmpty) {
        final filtered = InfiniteRadioService().filterDuplicates(radioTracks, [stem]);
        final newQueue = [stem, ...filtered];
        _audioHandler.setQueue(newQueue);
        debugPrint('[PlayerProvider] Queued ${filtered.length} relatable songs for "${stem.title}"');
      }
    } catch (e) {
      debugPrint('[PlayerProvider] playWithRadio error: $e');
    } finally {
      _isLoadingRadio = false;
      notifyListeners();
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index >= 0 && index < _audioHandler.currentQueue.length) {
      final target = _audioHandler.currentQueue[index];
      _position = Duration.zero;
      _duration = Duration(seconds: target.durationSec);
      _isBuffering = true;
      _activeStem = target;
      notifyListeners();
      await _audioHandler.playStem(target, preserveQueue: true);
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  // Fully functional seek for the Song Front/Back bar
  Future<void> seek(Duration target) async {
    _position = target;
    notifyListeners();
    await _audioHandler.seek(target);
  }

  Future<void> seekBy(int seconds) async {
    await _audioHandler.seekBy(Duration(seconds: seconds));
  }

  Future<void> skipNext() async {
    _isBuffering = true;
    notifyListeners();
    await _audioHandler.skipToNext();
  }

  Future<void> skipPrev() async {
    _isBuffering = true;
    notifyListeners();
    await _audioHandler.skipToPrevious();
  }

  Future<void> shufflePlay(List<Stem> stems) async {
    if (stems.isEmpty) return;
    _isShuffled = true;
    final shuffled = List<Stem>.from(stems)..shuffle();
    final firstStem = shuffled.first;
    _audioHandler.setShuffled(true, originalQueue: stems);
    await playStem(firstStem, queue: shuffled);
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _audioHandler.setShuffled(_isShuffled);
    notifyListeners();
  }

  void cycleLoopMode() {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    _audioHandler.setLoopMode(_loopMode);
    notifyListeners();
  }

  void addToQueue(Stem stem) {
    _audioHandler.addToQueue(stem);
    notifyListeners();
  }

  void playNext(Stem stem) {
    _audioHandler.playNext(stem);
    notifyListeners();
  }

  Future<void> _fetchLyrics(Stem stem) async {
    _isLoadingLyrics = true;
    _activeLyricIndex = -1;
    notifyListeners();

    try {
      final res = await LyricsService.fetchLyrics(
        stem.title,
        stem.artistName,
        stem.durationSec,
        stem.sourceId,
      );
      _lyrics = res;
    } catch (_) {
      _lyrics = null;
    } finally {
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  void _updateActiveLyricIndex() {
    if (_lyrics == null || !_lyrics!.isSynced || _lyrics!.lines.isEmpty) return;
    final idx = LyricsService.getActiveLineIndex(_lyrics!.lines, _position.inMilliseconds / 1000.0);
    if (idx != _activeLyricIndex) {
      _activeLyricIndex = idx;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeStemSub?.cancel();
    _playbackStateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }
}
