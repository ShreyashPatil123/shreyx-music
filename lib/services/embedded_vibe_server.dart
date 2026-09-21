import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

class EmbeddedVibeMember {
  final String id;
  final String name;
  final bool isHost;
  final int colorIndex;
  final int joinedAtSec;
  final WebSocket socket;

  EmbeddedVibeMember({
    required this.id,
    required this.name,
    required this.isHost,
    required this.colorIndex,
    required this.joinedAtSec,
    required this.socket,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
        'colorIndex': colorIndex,
        'joinedAtSec': joinedAtSec,
      };
}

class EmbeddedVibeRoom {
  final String code;
  final String name;
  String hostMemberId;
  final Map<String, EmbeddedVibeMember> members = {};
  final Map<String, Map<String, dynamic>> pendingJoins = {};
  final List<Map<String, dynamic>> queue = [];
  final List<Map<String, dynamic>> suggestions = [];
  Map<String, dynamic> playbackState = {
    'currentTrack': null,
    'isPlaying': false,
    'positionMs': 0,
    'serverTimeMs': 0,
    'hostId': '',
    'seq': 0,
    'queue': [],
  };

  EmbeddedVibeRoom({
    required this.code,
    required this.name,
    required this.hostMemberId,
  });

  Map<String, dynamic> getSnapshot() => {
        'code': code,
        'name': name,
        'hostId': hostMemberId,
        'members': members.values.map((m) => m.toJson()).toList(),
        'queue': queue,
        'playbackState': playbackState,
        'suggestions': suggestions,
      };

  void broadcast(String type, Map<String, dynamic> payload, {String? excludeMemberId}) {
    final msg = jsonEncode({'type': type, 'payload': payload});
    for (final member in members.values) {
      if (member.id == excludeMemberId) continue;
      try {
        member.socket.add(msg);
      } catch (e) {
        debugPrint('[EmbeddedVibeServer] Broadcast error to ${member.name}: $e');
      }
    }
  }
}

class EmbeddedVibeServer {
  static final EmbeddedVibeServer _instance = EmbeddedVibeServer._internal();
  factory EmbeddedVibeServer() => _instance;
  EmbeddedVibeServer._internal();

  HttpServer? _server;
  final Map<String, EmbeddedVibeRoom> _rooms = {};
  final Map<WebSocket, String> _socketToMemberId = {};
  final Map<WebSocket, String> _socketToRoomCode = {};

  int _port = 8080;
  bool get isRunning => _server != null;
  int get port => _port;

  String? _localIp;
  String? get localIp => _localIp;

  Future<String> start({int port = 8080}) async {
    if (_server != null) {
      return 'ws://127.0.0.1:$_port/ws';
    }

    _port = port;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    } catch (_) {
      // If port 8080 is busy, bind to any available dynamic port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
    }

    // Determine device LAN IP
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            _localIp = addr.address;
            break;
          }
        }
        if (_localIp != null) break;
      }
    } catch (e) {
      debugPrint('[EmbeddedVibeServer] IP detection error: $e');
    }

    _server!.listen(_handleHttpRequest);
    debugPrint('[EmbeddedVibeServer] Running on port $_port (LAN: $_localIp)');
    return 'ws://127.0.0.1:$_port/ws';
  }

  void _handleHttpRequest(HttpRequest request) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((socket) {
        _handleWebSocket(socket);
      }).catchError((err) {
        debugPrint('[EmbeddedVibeServer] Upgrade error: $err');
      });
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'server': 'ShreyX Embedded Vibe', 'rooms': _rooms.length}))
        ..close();
    }
  }

  void _handleWebSocket(WebSocket socket) {
    socket.listen(
      (data) => _onMessage(socket, data),
      onError: (err) => _onDisconnect(socket),
      onDone: () => _onDisconnect(socket),
      cancelOnError: true,
    );
  }

  void _onMessage(WebSocket socket, dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final payload = decoded['payload'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'ping':
          final clientTime = payload['client_time'] ?? DateTime.now().millisecondsSinceEpoch;
          _send(socket, 'pong', {
            'client_time': clientTime,
            'server_time': DateTime.now().millisecondsSinceEpoch,
          });
          break;

        case 'create_room':
          _handleCreateRoom(socket, payload);
          break;

        case 'join_room':
          _handleJoinRoom(socket, payload);
          break;

        case 'approve_join':
          _handleApproveJoin(socket, payload);
          break;

        case 'reject_join':
          _handleRejectJoin(socket, payload);
          break;

        case 'playback_action':
          _handlePlaybackAction(socket, payload);
          break;

        case 'suggest_song':
          _handleSuggestSong(socket, payload);
          break;

        case 'approve_suggestion':
          _handleApproveSuggestion(socket, payload);
          break;

        case 'reject_suggestion':
          _handleRejectSuggestion(socket, payload);
          break;

        case 'request_sync':
          _handleRequestSync(socket);
          break;

        case 'leave_room':
          _onDisconnect(socket);
          break;
      }
    } catch (e) {
      debugPrint('[EmbeddedVibeServer] Error processing message: $e');
    }
  }

  void _handleCreateRoom(WebSocket socket, Map<String, dynamic> payload) {
    final hostName = (payload['host_name'] as String? ?? '').trim();
    final roomName = (payload['room_name'] as String? ?? '').trim();

    final code = _generateRoomCode();
    final memberId = 'mem_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final sessionToken = 'sess_${DateTime.now().millisecondsSinceEpoch}';

    final hostMember = EmbeddedVibeMember(
      id: memberId,
      name: hostName.isNotEmpty ? hostName : 'Host',
      isHost: true,
      colorIndex: 0,
      joinedAtSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      socket: socket,
    );

    final room = EmbeddedVibeRoom(
      code: code,
      name: roomName.isNotEmpty ? roomName : "Host's Party",
      hostMemberId: memberId,
    );
    room.members[memberId] = hostMember;

    _rooms[code] = room;
    _socketToMemberId[socket] = memberId;
    _socketToRoomCode[socket] = code;

    _send(socket, 'room_created', {
      'room_code': code,
      'room_name': room.name,
      'member_id': memberId,
      'session_token': sessionToken,
      'snapshot': room.getSnapshot(),
    });
    debugPrint('[EmbeddedVibeServer] Room $code created by ${hostMember.name}');
  }

  void _handleJoinRoom(WebSocket socket, Map<String, dynamic> payload) {
    final code = (payload['room_code'] as String? ?? '').trim().toUpperCase();
    final userName = (payload['user_name'] as String? ?? 'Guest').trim();
    final room = _rooms[code];

    if (room == null) {
      _send(socket, 'error', {'code': 'ROOM_NOT_FOUND', 'message': 'Party room $code does not exist on this device.'});
      return;
    }

    final memberId = 'mem_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final joinReq = {
      'member_id': memberId,
      'user_name': userName.isNotEmpty ? userName : 'Guest',
      'created_at_sec': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    room.pendingJoins[memberId] = joinReq;
    _socketToMemberId[socket] = memberId;
    _socketToRoomCode[socket] = code;

    _send(socket, 'join_pending', {
      'room_code': code,
      'message': 'Waiting for host approval...',
    });

    final host = room.members[room.hostMemberId];
    if (host != null) {
      _send(host.socket, 'join_request', joinReq);
    }
  }

  void _handleApproveJoin(WebSocket socket, Map<String, dynamic> payload) {
    final memberId = payload['member_id'] as String?;
    final code = _socketToRoomCode[socket];
    if (code == null || memberId == null) return;
    final room = _rooms[code];
    if (room == null) return;

    final joinReq = room.pendingJoins.remove(memberId);
    if (joinReq == null) return;

    WebSocket? applicantSocket;
    for (final entry in _socketToMemberId.entries) {
      if (entry.value == memberId) {
        applicantSocket = entry.key;
        break;
      }
    }

    if (applicantSocket == null) return;

    final newMember = EmbeddedVibeMember(
      id: memberId,
      name: joinReq['user_name'] as String? ?? 'Guest',
      isHost: false,
      colorIndex: (room.members.length) % 6,
      joinedAtSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      socket: applicantSocket,
    );
    room.members[memberId] = newMember;

    _send(applicantSocket, 'room_joined', {
      'room_code': code,
      'member_id': memberId,
      'session_token': 'sess_${DateTime.now().millisecondsSinceEpoch}',
      'is_host': false,
      'snapshot': room.getSnapshot(),
    });

    room.broadcast('member_joined', newMember.toJson(), excludeMemberId: memberId);
    debugPrint('[EmbeddedVibeServer] Approved member ${newMember.name} in room $code');
  }

  void _handleRejectJoin(WebSocket socket, Map<String, dynamic> payload) {
    final memberId = payload['member_id'] as String?;
    final reason = payload['reason'] as String? ?? 'Host declined your request';
    final code = _socketToRoomCode[socket];
    if (code == null || memberId == null) return;
    final room = _rooms[code];
    if (room == null) return;

    room.pendingJoins.remove(memberId);

    for (final entry in _socketToMemberId.entries) {
      if (entry.value == memberId) {
        _send(entry.key, 'join_rejected', {'reason': reason});
        break;
      }
    }
  }

  void _handlePlaybackAction(WebSocket socket, Map<String, dynamic> payload) {
    final code = _socketToRoomCode[socket];
    if (code == null) return;
    final room = _rooms[code];
    if (room == null) return;

    final memberId = _socketToMemberId[socket];
    if (memberId != room.hostMemberId) {
      return;
    }

    final action = payload['action'] as String?;
    final currentTrack = payload['currentTrack'] as Map<String, dynamic>?;
    final isPlaying = payload['isPlaying'] as bool? ?? false;
    final positionMs = (payload['positionMs'] as num?)?.toInt() ?? 0;
    final seq = (payload['seq'] as num?)?.toInt() ?? 0;

    room.playbackState = {
      'action': action,
      'currentTrack': currentTrack,
      'isPlaying': isPlaying,
      'positionMs': positionMs,
      'serverTimeMs': DateTime.now().millisecondsSinceEpoch,
      'hostId': room.hostMemberId,
      'seq': seq,
      'queue': payload['queue'] ?? room.queue,
    };

    if (payload['queue'] is List) {
      room.queue
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(payload['queue'] as List));
    }

    room.broadcast('sync_state', room.playbackState, excludeMemberId: memberId);
  }

  void _handleSuggestSong(WebSocket socket, Map<String, dynamic> payload) {
    final code = _socketToRoomCode[socket];
    if (code == null) return;
    final room = _rooms[code];
    if (room == null) return;

    final suggId = 'sugg_${DateTime.now().millisecondsSinceEpoch}';
    final sugg = {
      'id': suggId,
      'stem': payload['stem'],
      'suggestedBy': _socketToMemberId[socket] ?? '',
      'suggesterName': payload['suggesterName'] ?? 'Member',
      'createdAtSec': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    room.suggestions.add(sugg);

    final host = room.members[room.hostMemberId];
    if (host != null) {
      _send(host.socket, 'new_suggestion', sugg);
    }
  }

  void _handleApproveSuggestion(WebSocket socket, Map<String, dynamic> payload) {
    final code = _socketToRoomCode[socket];
    if (code == null) return;
    final room = _rooms[code];
    if (room == null) return;

    final suggId = payload['suggestion_id'] as String?;
    final action = payload['action'] as String? ?? 'add_queue';
    room.suggestions.removeWhere((s) => s['id'] == suggId);

    room.broadcast('suggestion_resolved', {
      'suggestion_id': suggId,
      'status': 'approved',
      'action': action,
    });
  }

  void _handleRejectSuggestion(WebSocket socket, Map<String, dynamic> payload) {
    final code = _socketToRoomCode[socket];
    if (code == null) return;
    final room = _rooms[code];
    if (room == null) return;

    final suggId = payload['suggestion_id'] as String?;
    room.suggestions.removeWhere((s) => s['id'] == suggId);

    room.broadcast('suggestion_resolved', {
      'suggestion_id': suggId,
      'status': 'rejected',
    });
  }

  void _handleRequestSync(WebSocket socket) {
    final code = _socketToRoomCode[socket];
    if (code == null) return;
    final room = _rooms[code];
    if (room == null) return;

    _send(socket, 'sync_state', room.playbackState);
  }

  void _onDisconnect(WebSocket socket) {
    final memberId = _socketToMemberId.remove(socket);
    final code = _socketToRoomCode.remove(socket);

    if (code != null && memberId != null) {
      final room = _rooms[code];
      if (room != null) {
        final member = room.members.remove(memberId);
        room.pendingJoins.remove(memberId);

        if (member != null) {
          final wasHost = (memberId == room.hostMemberId);
          String newHostId = '';

          if (wasHost && room.members.isNotEmpty) {
            final nextHost = room.members.values.first;
            nextHost.socket.add(jsonEncode({
              'type': 'host_transferred',
              'payload': {'new_host_id': nextHost.id},
            }));
            room.hostMemberId = nextHost.id;
            newHostId = nextHost.id;
          }

          room.broadcast('member_left', {
            'member_id': memberId,
            'new_host_id': newHostId,
          });

          if (room.members.isEmpty) {
            _rooms.remove(code);
            debugPrint('[EmbeddedVibeServer] Room $code closed (empty)');
          }
        }
      }
    }
  }

  void _send(WebSocket socket, String type, Map<String, dynamic> payload) {
    try {
      socket.add(jsonEncode({'type': type, 'payload': payload}));
    } catch (e) {
      debugPrint('[EmbeddedVibeServer] Send error: $e');
    }
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> stop() async {
    for (final s in _socketToMemberId.keys) {
      try {
        await s.close();
      } catch (_) {}
    }
    _socketToMemberId.clear();
    _socketToRoomCode.clear();
    _rooms.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('[EmbeddedVibeServer] Server stopped');
  }
}
