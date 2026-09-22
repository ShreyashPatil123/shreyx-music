import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/stem.dart';
import '../models/vibe_models.dart';
import '../services/audio_handler.dart';
import '../services/vibe_service.dart';

class VibeProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ShrexAudioHandler _audioHandler;
  final VibeService _service = VibeService();

  VibeRoom? _room;
  final List<Map<String, dynamic>> _pendingJoins = [];
  final List<VibeSongSuggestion> _pendingSuggestions = [];
  String? _toastMessage;

  // Playback Loop Prevention Guard
  bool _isApplyingRemoteState = false;
  String? _lastBroadcastTrackId;
  bool? _lastBroadcastIsPlaying;
  int _lastBroadcastPositionMs = -1;
  Timer? _hostBroadcastDebounce;
  Timer? _speedResetTimer;

  DateTime? _resumedAt;

  // Subscriptions
  final List<StreamSubscription> _subscriptions = [];

  VibeRoom? get room => _room;
  bool get isInRoom => _room != null;
  bool get isConnected => _service.status == VibeConnectionStatus.inRoom || _service.status == VibeConnectionStatus.connected;
  bool get isReconnecting => _room != null && !isConnected;

  /// Only show the reconnecting banner if we've been disconnected for > 3 seconds,
  /// and allow a 3-second grace period after app resume so fast reconnects never flash the banner.
  bool get showReconnectingBanner {
    if (!isReconnecting) return false;
    if (_resumedAt != null && DateTime.now().difference(_resumedAt!).inSeconds < 3) {
      return false;
    }
    final disc = _service.disconnectedAt;
    if (disc == null) return false;
    return DateTime.now().difference(disc).inSeconds >= 3;
  }

  bool get isHost => _service.isHost;
  bool get isWaitingApproval => _service.status == VibeConnectionStatus.waitingApproval;
  VibeConnectionStatus get connectionStatus => _service.status;
  List<Map<String, dynamic>> get pendingJoins => List.unmodifiable(_pendingJoins);
  List<VibeSongSuggestion> get pendingSuggestions => List.unmodifiable(_pendingSuggestions);
  String? get toastMessage => _toastMessage;
  VibeConfig get config => _service.config;

  /// In ShreyX Vibe, only host can control playback & queue. Members can only view & suggest.
  bool get canControlPlayback => !isInRoom || isHost;

  VibeProvider({required ShrexAudioHandler audioHandler}) : _audioHandler = audioHandler {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumedAt = DateTime.now();
      if (_room != null || _service.currentRoomCode != null) {
        debugPrint('[ShreyXVibe] App resumed while in room (${_room?.code ?? _service.currentRoomCode}). Fast reconnecting...');
        _service.reconnectNow();
      }
    }
  }

  Future<void> _init() async {
    await _service.init();
    _subscribeToService();
    _subscribeToAudioHandler();
  }

  void _subscribeToService() {
    _subscriptions.add(_service.statusStream.listen((status) {
      // Keep _room intact during temporary socket drops (app minimization or cellular switches)
      notifyListeners();
    }));

    _subscriptions.add(_service.roomSnapshotStream.listen((snapshot) {
      _room = snapshot;
      _pendingSuggestions.clear();
      _pendingSuggestions.addAll(snapshot.suggestions);
      notifyListeners();

      // If member, synchronize local playback with room snapshot
      if (!_service.isHost) {
        _applyRemotePlaybackState(snapshot.playbackState);
      }
    }));

    _subscriptions.add(_service.syncStateStream.listen((state) {
      if (_room != null) {
        _room = _room!.copyWith(
          playbackState: state,
          queue: state.queue,
        );
        notifyListeners();
      }

      // Member receives authoritative sync
      if (!_service.isHost) {
        _applyRemotePlaybackState(state);
      }
    }));

    _subscriptions.add(_service.joinRequestStream.listen((req) {
      _pendingJoins.removeWhere((item) => item['member_id'] == req['member_id']);
      _pendingJoins.add(req);
      _toastMessage = '${req['user_name']} wants to join the party!';
      notifyListeners();
    }));

    _subscriptions.add(_service.suggestionStream.listen((sugg) {
      _pendingSuggestions.removeWhere((item) => item.id == sugg.id);
      _pendingSuggestions.add(sugg);
      _toastMessage = '${sugg.suggesterName} requested "${sugg.stem.title}"';
      notifyListeners();
    }));

    _subscriptions.add(_service.messageStream.listen((msg) {
      _toastMessage = msg;
      final lower = msg.toLowerCase();
      if (lower.contains('not found') || lower.contains('room does not exist') || lower.contains('closed') || lower.contains('ended')) {
        _room = null;
        _pendingJoins.clear();
        _pendingSuggestions.clear();
        _service.leaveRoom();
      }
      notifyListeners();
    }));

    _subscriptions.add(_service.kickedStream.listen((reason) {
      _room = null;
      _pendingJoins.clear();
      _pendingSuggestions.clear();
      _toastMessage = reason;
      _service.leaveRoom();
      notifyListeners();
    }));
  }

  /// Observe Host's local AudioHandler and broadcast changes once (Loop Prevention)
  void _subscribeToAudioHandler() {
    _subscriptions.add(_audioHandler.activeStemStream.listen((stem) {
      if (!isInRoom || !_service.isHost || _isApplyingRemoteState) return;
      if (stem != null && stem.id != _lastBroadcastTrackId) {
        _lastBroadcastTrackId = stem.id;
        _broadcastHostPlayback('change_track', stem: stem, positionMs: 0);
      }
    }));

    _subscriptions.add(_audioHandler.playbackState.listen((playbackState) {
      if (!isInRoom || !_service.isHost || _isApplyingRemoteState) return;

      final isPlaying = playbackState.playing;
      final posMs = playbackState.updatePosition.inMilliseconds;

      // Deduplicate state changes
      if (_lastBroadcastIsPlaying != isPlaying) {
        _lastBroadcastIsPlaying = isPlaying;
        _broadcastHostPlayback(isPlaying ? 'play' : 'pause', positionMs: posMs);
      }
    }));

    // Listen to user manual seek in Host mode
    _subscriptions.add(_audioHandler.player.positionStream.listen((pos) {
      if (!isInRoom || !_service.isHost || _isApplyingRemoteState) return;

      final posMs = pos.inMilliseconds;
      // If position jumped significantly (> 2.5s) outside normal linear progression, broadcast seek
      if ((posMs - _lastBroadcastPositionMs).abs() > 2500) {
        _hostBroadcastDebounce?.cancel();
        _hostBroadcastDebounce = Timer(const Duration(milliseconds: 150), () {
          _lastBroadcastPositionMs = posMs;
          _broadcastHostPlayback('seek', positionMs: posMs);
        });
      } else {
        _lastBroadcastPositionMs = posMs;
      }
    }));
  }

  void _broadcastHostPlayback(String action, {Stem? stem, int positionMs = 0}) {
    _service.sendPlaybackAction(
      action,
      stem: stem ?? _audioHandler.activeStem,
      positionMs: positionMs,
    );
  }

  /// Applies remote state from server to local AudioHandler with drift correction
  Future<void> _applyRemotePlaybackState(VibePlaybackState state) async {
    _isApplyingRemoteState = true;

    try {
      final remoteTrack = state.currentTrack;
      final isPlaying = state.isPlaying;
      final serverPosMs = state.positionMs;
      final serverTimeMs = state.serverTimeMs;

      // 1. Clock-offset and elapsed time calculation
      final now = DateTime.now().millisecondsSinceEpoch;
      final adjustedServerTime = serverTimeMs - _service.clockOffsetMs;
      int elapsedMs = now - adjustedServerTime;
      if (!isPlaying || elapsedMs < 0 || elapsedMs > 30000) {
        elapsedMs = 0;
      }

      final targetPosMs = serverPosMs + elapsedMs;

      // 2. Track matching and stream resolution
      final currentStem = _audioHandler.activeStem;
      final bool trackChanged = remoteTrack != null &&
          (currentStem == null || currentStem.sourceId != remoteTrack.sourceId);

      if (trackChanged) {
        debugPrint('[VibeProvider] Remote track change: "${remoteTrack.title}" at ${targetPosMs}ms');
        await _audioHandler.playStem(remoteTrack, queue: [remoteTrack]);
        if (targetPosMs > 500) {
          await _audioHandler.seek(Duration(milliseconds: targetPosMs));
        }
        if (!isPlaying) {
          await _audioHandler.pause();
        }
        return;
      }

      // 3. Play/Pause state alignment
      if (_audioHandler.player.playing != isPlaying) {
        if (isPlaying) {
          await _audioHandler.play();
        } else {
          await _audioHandler.pause();
        }
      }

      // 4. Smooth Drift Correction
      if (remoteTrack != null && isPlaying) {
        final currentPosMs = _audioHandler.player.position.inMilliseconds;
        final driftMs = currentPosMs - targetPosMs; // positive: ahead, negative: behind

        if (driftMs.abs() > 2000) {
          // Large drift (> 2.0s): seek immediately to authoritative position
          debugPrint('[VibeProvider] Large drift (${driftMs}ms). Seeking to ${targetPosMs}ms');
          await _audioHandler.seek(Duration(milliseconds: targetPosMs));
        } else if (driftMs.abs() > 500) {
          // Moderate drift (0.5s – 2.0s): smooth speed correction without stutter
          final speed = driftMs < 0 ? 1.05 : 0.95;
          await _audioHandler.player.setSpeed(speed);
          _speedResetTimer?.cancel();
          _speedResetTimer = Timer(const Duration(milliseconds: 1500), () {
            _audioHandler.player.setSpeed(1.0);
          });
        }
      }
    } catch (e) {
      debugPrint('[VibeProvider] Error applying remote state: $e');
    } finally {
      // Loop prevention debounce: allow local events to settle before re-enabling outbound broadcasting
      Future.delayed(const Duration(milliseconds: 250), () {
        _isApplyingRemoteState = false;
      });
    }
  }

  // --- Public Actions for UI ---

  Future<VibeRoom> createRoom({
    required String hostName,
    required String roomName,
  }) async {
    final room = await _service.createRoom(
      hostName,
      roomName,
    );
    _room = room;
    notifyListeners();
    return room;
  }

  Future<bool> joinRoom({
    required String roomCode,
    required String userName,
  }) async {
    final ok = await _service.joinRoom(
      roomCode,
      userName,
    );
    notifyListeners();
    return ok;
  }

  void approveJoin(String memberId) {
    _pendingJoins.removeWhere((item) => item['member_id'] == memberId);
    _service.approveJoin(memberId);
    notifyListeners();
  }

  void rejectJoin(String memberId, {String? reason}) {
    _pendingJoins.removeWhere((item) => item['member_id'] == memberId);
    _service.rejectJoin(memberId, reason: reason);
    notifyListeners();
  }

  void suggestSong(Stem stem) {
    _service.suggestSong(stem);
    _toastMessage = 'Song requested! Waiting for host approval.';
    notifyListeners();
  }

  /// Host directly plays a song immediately across the party
  Future<void> hostPlayNow(Stem stem) async {
    if (!isHost) return;
    try {
      await _audioHandler.playStem(stem, queue: [stem]);
      _service.sendPlaybackAction('change_track', stem: stem, positionMs: 0);
      if (_room != null) {
        _room = _room!.copyWith(
          playbackState: _room!.playbackState.copyWith(
            currentTrack: stem,
            isPlaying: true,
            positionMs: 0,
          ),
        );
      }
      _toastMessage = 'Now playing "${stem.title}"';
      notifyListeners();
    } catch (e) {
      debugPrint('[VibeProvider] hostPlayNow error: $e');
    }
  }

  /// Host directly appends a song to the party queue
  void hostAddToQueue(Stem stem) {
    if (!isHost) return;
    _audioHandler.addToQueue(stem);
    _service.sendPlaybackAction('queue_add', stem: stem);
    if (_room != null) {
      final newQueue = [..._room!.queue, stem];
      _room = _room!.copyWith(
        queue: newQueue,
        playbackState: _room!.playbackState.copyWith(queue: newQueue),
      );
    }
    _toastMessage = 'Added "${stem.title}" to party queue';
    notifyListeners();
  }

  /// Host directly sets a song to play next in the party
  void hostPlayNext(Stem stem) {
    if (!isHost) return;
    _audioHandler.playNext(stem);
    _service.sendPlaybackAction('queue_play_next', stem: stem);
    if (_room != null) {
      final newQueue = [stem, ..._room!.queue];
      _room = _room!.copyWith(
        queue: newQueue,
        playbackState: _room!.playbackState.copyWith(queue: newQueue),
      );
    }
    _toastMessage = 'Playing "${stem.title}" next in party';
    notifyListeners();
  }

  void approveSuggestion(String suggestionId, {required bool playNow}) {
    _pendingSuggestions.removeWhere((s) => s.id == suggestionId);
    _service.approveSuggestion(suggestionId, playNow ? 'play_now' : 'add_to_queue');
    notifyListeners();
  }

  void rejectSuggestion(String suggestionId) {
    _pendingSuggestions.removeWhere((s) => s.id == suggestionId);
    _service.rejectSuggestion(suggestionId);
    notifyListeners();
  }

  void leaveRoom() {
    _service.leaveRoom();
    _room = null;
    _pendingJoins.clear();
    _pendingSuggestions.clear();
    notifyListeners();
  }

  void kickMember(String memberId) {
    _service.kickMember(memberId);
  }

  void transferHost(String newHostId) {
    _service.transferHost(newHostId);
  }

  Future<void> updateConfig({bool? isDevMode, String? customProdUrl, String? customDevUrl}) async {
    // ShreyX Vibe operates strictly via the public cloud server
  }

  void clearToast() {
    _toastMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _hostBroadcastDebounce?.cancel();
    _speedResetTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
