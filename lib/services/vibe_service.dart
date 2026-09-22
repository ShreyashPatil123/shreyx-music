import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/stem.dart';
import '../models/vibe_models.dart';

class VibeService {
  static final VibeService _instance = VibeService._internal();
  factory VibeService() => _instance;
  VibeService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  VibeConnectionStatus _status = VibeConnectionStatus.disconnected;
  final VibeConfig _config = const VibeConfig();
  static const _nativeChannel = MethodChannel('com.shreyx.player/native_stream');

  String? _sessionToken;
  String? _currentRoomCode;
  String? _currentMemberId;
  String? _userName;
  bool _isHost = false;

  Completer<VibeRoom>? _createRoomCompleter;
  Completer<bool>? _joinRoomCompleter;

  // Clock synchronization
  int _clockOffsetMs = 0;
  int _lastSyncedSeq = -1;
  int _lastSyncedServerTimeMs = 0;

  // Track when disconnected for delayed reconnecting banner
  DateTime? _disconnectedAt;

  // Stream Controllers
  final _statusCtrl = StreamController<VibeConnectionStatus>.broadcast();
  final _syncStateCtrl = StreamController<VibePlaybackState>.broadcast();
  final _joinRequestCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _suggestionCtrl = StreamController<VibeSongSuggestion>.broadcast();
  final _roomSnapshotCtrl = StreamController<VibeRoom>.broadcast();
  final _messageCtrl = StreamController<String>.broadcast();
  final _kickedCtrl = StreamController<String>.broadcast();

  // Getters
  VibeConnectionStatus get status => _status;
  VibeConfig get config => _config;
  String? get currentRoomCode => _currentRoomCode;
  String? get currentMemberId => _currentMemberId;
  String? get userName => _userName;
  bool get isHost => _isHost;
  int get clockOffsetMs => _clockOffsetMs;
  DateTime? get disconnectedAt => _disconnectedAt;

  Stream<VibeConnectionStatus> get statusStream => _statusCtrl.stream;
  Stream<VibePlaybackState> get syncStateStream => _syncStateCtrl.stream;
  Stream<Map<String, dynamic>> get joinRequestStream => _joinRequestCtrl.stream;
  Stream<VibeSongSuggestion> get suggestionStream => _suggestionCtrl.stream;
  Stream<VibeRoom> get roomSnapshotStream => _roomSnapshotCtrl.stream;
  Stream<String> get messageStream => _messageCtrl.stream;
  Stream<String> get kickedStream => _kickedCtrl.stream;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString('vibe_session_token');
    _userName = prefs.getString('vibe_user_name') ?? 'Music Lover';
    _currentRoomCode = prefs.getString('vibe_room_code');
  }

  void _setStatus(VibeConnectionStatus s) {
    if (_status != s) {
      _status = s;
      // Track disconnect timestamp for delayed reconnecting banner
      if (s == VibeConnectionStatus.disconnected || s == VibeConnectionStatus.error) {
        _disconnectedAt ??= DateTime.now();
      } else if (s == VibeConnectionStatus.connected || s == VibeConnectionStatus.inRoom) {
        _disconnectedAt = null;
      }
      _statusCtrl.add(s);
    }
  }

  // Connect to public cloud WebSocket server with cold-start retry handling
  Future<void> connect() async {
    final targetUrl = Uri.parse(_config.activeWsUrl);

    if (_status == VibeConnectionStatus.connected && _channel != null) {
      return;
    }

    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (_) {}
      _channel = null;
    }

    _setStatus(VibeConnectionStatus.connecting);
    debugPrint('[ShreyXVibe] Connecting to cloud server: $targetUrl');

    int attempts = 0;
    const maxAttempts = 5;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        _channel = WebSocketChannel.connect(targetUrl);
        await _channel!.ready.timeout(const Duration(seconds: 10));

        _channelSub?.cancel();
        _channelSub = _channel!.stream.listen(
          _onMessageReceived,
          onError: _onError,
          onDone: _onDone,
          cancelOnError: true,
        );

        _setStatus(VibeConnectionStatus.connected);
        _reconnectAttempts = 0;
        _startHeartbeat();

        // If we had an active session, attempt seamless reconnection
        if (_currentRoomCode != null && _sessionToken != null) {
          debugPrint('[ShreyXVibe] Resuming session in room: $_currentRoomCode');
          _send('join_room', {
            'room_code': _currentRoomCode,
            'user_name': _userName ?? 'Guest',
            'session_token': _sessionToken,
          });
        }
        return;
      } catch (e) {
        debugPrint('[ShreyXVibe] Connection attempt $attempts/$maxAttempts failed: $e');
        if (_channel != null) {
          try {
            await _channel!.sink.close();
          } catch (_) {}
          _channel = null;
        }

        if (attempts >= maxAttempts) {
          _setStatus(VibeConnectionStatus.error);
          _onError(e);
          throw TimeoutException(
            'Could not reach ShreyX Vibe cloud server. Please verify your internet connection and try again.',
          );
        }

        // Exponential backoff with jitter for Render free cold start (takes ~30s)
        final delaySec = 2 + (attempts * 2) + Random().nextInt(2);
        debugPrint('[ShreyXVibe] Retrying connection in ${delaySec}s for server wake-up...');
        await Future.delayed(Duration(seconds: delaySec));
      }
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _send('ping', {'client_time': now});
    });
  }

  void _onError(dynamic error) {
    debugPrint('[ShreyXVibe] WebSocket error: $error');
    _setStatus(VibeConnectionStatus.error);
    if (_createRoomCompleter != null && !_createRoomCompleter!.isCompleted) {
      _createRoomCompleter!.completeError(error);
    }
    if (_joinRoomCompleter != null && !_joinRoomCompleter!.isCompleted) {
      _joinRoomCompleter!.completeError(error);
    }
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[ShreyXVibe] WebSocket connection closed');
    _setStatus(VibeConnectionStatus.disconnected);
    _pingTimer?.cancel();
    _scheduleReconnect();
  }

  int _reconnectAttempts = 0;
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_currentRoomCode == null) return; // Only auto-reconnect if user was in a room

    final delaySec = min(pow(2, _reconnectAttempts).toInt() + Random().nextInt(2), 15);
    _reconnectAttempts++;
    debugPrint('[ShreyXVibe] Scheduling reconnect attempt $_reconnectAttempts in ${delaySec}s...');

    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      await connect();
    });
  }

  void _send(String type, Map<String, dynamic> payload) {
    if (_channel == null || _status == VibeConnectionStatus.disconnected) {
      return;
    }

    try {
      final jsonMsg = jsonEncode({
        'type': type,
        'payload': payload,
      });
      _channel!.sink.add(jsonMsg);
    } catch (e) {
      debugPrint('[ShreyXVibe] Send error: $e');
    }
  }

  void _onMessageReceived(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final payload = decoded['payload'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'pong':
          final clientTime = (payload['client_time'] as num?)?.toInt() ?? 0;
          final serverTime = (payload['server_time'] as num?)?.toInt() ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          final rtt = now - clientTime;
          _clockOffsetMs = serverTime - (clientTime + (rtt ~/ 2));
          break;

        case 'room_created':
          _currentRoomCode = payload['room_code'] as String?;
          _currentMemberId = payload['member_id'] as String?;
          _sessionToken = payload['session_token'] as String?;
          _isHost = true;
          _reconnectAttempts = 0;
          _saveSession();
          _acquireWakeLock();
          _setStatus(VibeConnectionStatus.inRoom);

          if (payload['snapshot'] != null) {
            final snap = VibeRoom.fromSnapshot(payload['snapshot'] as Map<String, dynamic>);
            _roomSnapshotCtrl.add(snap);
            if (_createRoomCompleter != null && !_createRoomCompleter!.isCompleted) {
              _createRoomCompleter!.complete(snap);
            }
          }
          break;

        case 'join_pending':
          _setStatus(VibeConnectionStatus.waitingApproval);
          final msg = payload['message'] as String? ?? 'Waiting for host approval...';
          _messageCtrl.add(msg);
          if (_joinRoomCompleter != null && !_joinRoomCompleter!.isCompleted) {
            _joinRoomCompleter!.complete(true);
          }
          break;

        case 'join_request':
          _joinRequestCtrl.add(payload);
          break;

        case 'room_joined':
          _currentRoomCode = payload['room_code'] as String?;
          _currentMemberId = payload['member_id'] as String?;
          _sessionToken = payload['session_token'] as String?;
          _isHost = payload['is_host'] as bool? ?? false;
          _reconnectAttempts = 0;
          _saveSession();
          _acquireWakeLock();
          _setStatus(VibeConnectionStatus.inRoom);

          if (payload['snapshot'] != null) {
            final snap = VibeRoom.fromSnapshot(payload['snapshot'] as Map<String, dynamic>);
            _roomSnapshotCtrl.add(snap);
          }
          if (_joinRoomCompleter != null && !_joinRoomCompleter!.isCompleted) {
            _joinRoomCompleter!.complete(true);
          }
          break;

        case 'join_rejected':
          _setStatus(VibeConnectionStatus.connected);
          _currentRoomCode = null;
          final reason = payload['reason'] as String? ?? 'Host declined your request.';
          _messageCtrl.add(reason);
          if (_joinRoomCompleter != null && !_joinRoomCompleter!.isCompleted) {
            _joinRoomCompleter!.completeError(Exception(reason));
          }
          break;

        case 'sync_state':
          _handleSyncState(payload);
          break;

        case 'new_suggestion':
          final sugg = VibeSongSuggestion.fromJson(payload);
          _suggestionCtrl.add(sugg);
          break;

        case 'suggestion_resolved':
          final status = payload['status'] as String? ?? '';
          final action = payload['action'] as String? ?? '';
          if (status == 'approved') {
            _messageCtrl.add(action == 'play_now' ? 'Song played now by host!' : 'Song added to queue!');
          }
          break;

        case 'member_joined':
          final member = VibeMember.fromJson(payload);
          _messageCtrl.add('${member.name} joined the party!');
          requestSync();
          break;

        case 'member_left':
          final leftId = payload['member_id'] as String? ?? '';
          debugPrint('[ShreyXVibe] Member left room: $leftId');
          final newHostId = payload['new_host_id'] as String? ?? '';
          if (newHostId == _currentMemberId) {
            _isHost = true;
            _messageCtrl.add('You are now the room host!');
          }
          requestSync();
          break;

        case 'kicked':
          final reason = payload['reason'] as String? ?? 'Removed from room';
          _currentRoomCode = null;
          _releaseWakeLock();
          _clearSavedRoomCode();
          _setStatus(VibeConnectionStatus.connected);
          _kickedCtrl.add(reason);
          break;

        case 'host_transferred':
          final newHostId = payload['new_host_id'] as String? ?? '';
          _isHost = (newHostId == _currentMemberId);
          if (_isHost) {
            _messageCtrl.add('Host controls transferred to you!');
          }
          requestSync();
          break;

        case 'error':
          final msg = payload['message'] as String? ?? 'An error occurred';
          _messageCtrl.add(msg);
          if (_createRoomCompleter != null && !_createRoomCompleter!.isCompleted) {
            _createRoomCompleter!.completeError(Exception(msg));
          }
          if (_joinRoomCompleter != null && !_joinRoomCompleter!.isCompleted) {
            _joinRoomCompleter!.completeError(Exception(msg));
          }
          break;
      }
    } catch (e) {
      debugPrint('[ShreyXVibe] Message decode error: $e');
    }
  }

  void _handleSyncState(Map<String, dynamic> payload) {
    final seq = (payload['seq'] as num?)?.toInt() ?? 0;
    final serverTime = (payload['server_time_ms'] as num?)?.toInt() ?? 0;

    // Out-of-order message rejection: safe drop if packet is older than last seen
    if (seq > 0 && seq < _lastSyncedSeq) {
      debugPrint('[ShreyXVibe] Discarding out-of-order sync seq $seq (last: $_lastSyncedSeq)');
      return;
    }
    if (serverTime > 0 && serverTime < _lastSyncedServerTimeMs) {
      debugPrint('[ShreyXVibe] Discarding expired sync serverTime $serverTime (last: $_lastSyncedServerTimeMs)');
      return;
    }

    _lastSyncedSeq = seq;
    _lastSyncedServerTimeMs = serverTime;

    final state = VibePlaybackState.fromJson(payload);
    _syncStateCtrl.add(state);
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessionToken != null) {
      await prefs.setString('vibe_session_token', _sessionToken!);
    }
    if (_userName != null) {
      await prefs.setString('vibe_user_name', _userName!);
    }
    if (_currentRoomCode != null) {
      await prefs.setString('vibe_room_code', _currentRoomCode!);
    }
  }

  Future<void> _clearSavedRoomCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vibe_room_code');
  }

  Future<void> _acquireWakeLock() async {
    try {
      await _nativeChannel.invokeMethod('acquireVibeWakeLock');
      debugPrint('[ShreyXVibe] Acquired partial wake lock for Vibe room');
    } catch (e) {
      debugPrint('[ShreyXVibe] Failed to acquire wake lock: $e');
    }
  }

  Future<void> _releaseWakeLock() async {
    try {
      await _nativeChannel.invokeMethod('releaseVibeWakeLock');
      debugPrint('[ShreyXVibe] Released partial wake lock');
    } catch (e) {
      debugPrint('[ShreyXVibe] Failed to release wake lock: $e');
    }
  }

  // --- Public Action Emitters ---

  Future<VibeRoom> createRoom(
    String hostName,
    String roomName,
  ) async {
    _userName = hostName;
    _createRoomCompleter = Completer<VibeRoom>();

    await connect();

    _send('create_room', {
      'host_name': hostName,
      'room_name': roomName,
    });

    return await _createRoomCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _setStatus(VibeConnectionStatus.error);
        throw TimeoutException(
          'Connection to ShreyX Vibe timed out. Please check your internet connection and try again.',
        );
      },
    );
  }

  Future<bool> joinRoom(String roomCode, String userName) async {
    _userName = userName;
    _currentRoomCode = roomCode.toUpperCase().trim();
    _joinRoomCompleter = Completer<bool>();

    await connect();

    _send('join_room', {
      'room_code': _currentRoomCode,
      'user_name': userName,
      'session_token': _sessionToken ?? '',
    });

    return await _joinRoomCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('Timed out joining party $roomCode. Ensure the party is active.');
      },
    );
  }

  void approveJoin(String memberId) {
    _send('approve_join', {'member_id': memberId});
  }

  void rejectJoin(String memberId, {String? reason}) {
    _send('reject_join', {
      'member_id': memberId,
      'reason': reason ?? 'Host declined your request',
    });
  }

  void sendPlaybackAction(
    String action, {
    Stem? stem,
    int positionMs = 0,
    int? index,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _send('playback_action', {
      'action': action,
      'stem': stem?.toJson(),
      'position_ms': positionMs,
      'timestamp': now,
      if (index != null) 'index': index,
    });
  }

  void suggestSong(Stem stem) {
    _send('suggest_song', {
      'stem': stem.toJson(),
    });
  }

  void approveSuggestion(String suggestionId, String action) {
    _send('approve_suggestion', {
      'suggestion_id': suggestionId,
      'action': action, // 'play_now' or 'add_to_queue'
    });
  }

  void rejectSuggestion(String suggestionId) {
    _send('reject_suggestion', {
      'suggestion_id': suggestionId,
    });
  }

  void requestSync() {
    _send('request_sync', {});
  }

  void leaveRoom() {
    _send('leave_room', {});
    _currentRoomCode = null;
    _currentMemberId = null;
    _isHost = false;
    _reconnectTimer?.cancel();
    _releaseWakeLock();
    _clearSavedRoomCode();
    _setStatus(VibeConnectionStatus.connected);
  }

  void kickMember(String memberId) {
    _send('kick_member', {'member_id': memberId});
  }

  void transferHost(String newHostId) {
    _send('transfer_host', {'new_host_id': newHostId});
  }

  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(VibeConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusCtrl.close();
    _syncStateCtrl.close();
    _joinRequestCtrl.close();
    _suggestionCtrl.close();
    _roomSnapshotCtrl.close();
    _messageCtrl.close();
    _kickedCtrl.close();
  }
}
