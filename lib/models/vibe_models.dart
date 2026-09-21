import '../models/stem.dart';

enum VibeConnectionStatus {
  disconnected,
  connecting,
  connected,
  waitingApproval,
  inRoom,
  error,
}

class VibeMember {
  final String id;
  final String name;
  final bool isHost;
  final int colorIndex;
  final int joinedAtSec;

  const VibeMember({
    required this.id,
    required this.name,
    required this.isHost,
    this.colorIndex = 0,
    this.joinedAtSec = 0,
  });

  factory VibeMember.fromJson(Map<String, dynamic> json) => VibeMember(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Guest',
        isHost: json['isHost'] as bool? ?? false,
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        joinedAtSec: (json['joinedAtSec'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
        'colorIndex': colorIndex,
        'joinedAtSec': joinedAtSec,
      };
}

class VibeSongSuggestion {
  final String id;
  final Stem stem;
  final String suggestedBy;
  final String suggesterName;
  final int createdAtSec;

  const VibeSongSuggestion({
    required this.id,
    required this.stem,
    required this.suggestedBy,
    required this.suggesterName,
    this.createdAtSec = 0,
  });

  factory VibeSongSuggestion.fromJson(Map<String, dynamic> json) => VibeSongSuggestion(
        id: json['id'] as String? ?? '',
        stem: Stem.fromJson(json['stem'] as Map<String, dynamic>),
        suggestedBy: json['suggestedBy'] as String? ?? '',
        suggesterName: json['suggesterName'] as String? ?? 'Member',
        createdAtSec: (json['createdAtSec'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stem': stem.toJson(),
        'suggestedBy': suggestedBy,
        'suggesterName': suggesterName,
        'createdAtSec': createdAtSec,
      };
}

class VibePlaybackState {
  final Stem? currentTrack;
  final bool isPlaying;
  final int positionMs;
  final int serverTimeMs;
  final String hostId;
  final int seq;
  final List<Stem> queue;

  const VibePlaybackState({
    this.currentTrack,
    this.isPlaying = false,
    this.positionMs = 0,
    this.serverTimeMs = 0,
    this.hostId = '',
    this.seq = 0,
    this.queue = const [],
  });

  factory VibePlaybackState.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['queue'] as List<dynamic>? ?? [];
    return VibePlaybackState(
      currentTrack: json['current_track'] != null
          ? Stem.fromJson(json['current_track'] as Map<String, dynamic>)
          : null,
      isPlaying: json['is_playing'] as bool? ?? false,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      serverTimeMs: (json['server_time_ms'] as num?)?.toInt() ?? 0,
      hostId: json['host_id'] as String? ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      queue: rawQueue.map((e) => Stem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'current_track': currentTrack?.toJson(),
        'is_playing': isPlaying,
        'position_ms': positionMs,
        'server_time_ms': serverTimeMs,
        'host_id': hostId,
        'seq': seq,
        'queue': queue.map((e) => e.toJson()).toList(),
      };
}

class VibeRoom {
  final String code;
  final String name;
  final String hostId;
  final List<VibeMember> members;
  final List<Stem> queue;
  final VibePlaybackState playbackState;
  final List<VibeSongSuggestion> suggestions;

  const VibeRoom({
    required this.code,
    required this.name,
    required this.hostId,
    required this.members,
    required this.queue,
    required this.playbackState,
    this.suggestions = const [],
  });

  bool isHost(String memberId) => hostId == memberId;

  factory VibeRoom.fromSnapshot(Map<String, dynamic> json) {
    final membersRaw = json['members'] as List<dynamic>? ?? [];
    final queueRaw = json['queue'] as List<dynamic>? ?? [];
    final suggRaw = json['suggestions'] as List<dynamic>? ?? [];

    return VibeRoom(
      code: json['roomCode'] as String? ?? '',
      name: json['roomName'] as String? ?? 'ShreyX Party',
      hostId: json['hostId'] as String? ?? '',
      members: membersRaw.map((e) => VibeMember.fromJson(e as Map<String, dynamic>)).toList(),
      queue: queueRaw.map((e) => Stem.fromJson(e as Map<String, dynamic>)).toList(),
      playbackState: VibePlaybackState(
        currentTrack: json['currentTrack'] != null
            ? Stem.fromJson(json['currentTrack'] as Map<String, dynamic>)
            : null,
        isPlaying: json['isPlaying'] as bool? ?? false,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        serverTimeMs: (json['serverTimeMs'] as num?)?.toInt() ?? 0,
        hostId: json['hostId'] as String? ?? '',
        seq: (json['seq'] as num?)?.toInt() ?? 0,
      ),
      suggestions: suggRaw.map((e) => VibeSongSuggestion.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  VibeRoom copyWith({
    String? code,
    String? name,
    String? hostId,
    List<VibeMember>? members,
    List<Stem>? queue,
    VibePlaybackState? playbackState,
    List<VibeSongSuggestion>? suggestions,
  }) {
    return VibeRoom(
      code: code ?? this.code,
      name: name ?? this.name,
      hostId: hostId ?? this.hostId,
      members: members ?? this.members,
      queue: queue ?? this.queue,
      playbackState: playbackState ?? this.playbackState,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

class VibeConfig {
  static const String defaultProdWsUrl = String.fromEnvironment(
    'SHREYX_VIBE_SERVER_URL',
    defaultValue: 'wss://shreyx-vibe.onrender.com/ws',
  );

  const VibeConfig();

  String get activeWsUrl => defaultProdWsUrl;
  bool get isDevMode => false;
  String get customProdUrl => '';
  String get customDevUrl => '';
}
