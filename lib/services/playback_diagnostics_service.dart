import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class PlaybackDiagnosticsSession {
  final String sessionId;
  final String stemId;
  final String title;
  final String artist;
  final String sourceId;
  final String platform;
  final String osVersion;
  final String deviceModel;
  final DateTime tappedAt;

  DateTime? metadataAvailableAt;
  DateTime? searchToYouTubeResolutionAt;
  DateTime? nativeStartAt;
  DateTime? nativeCompleteAt;
  DateTime? dartStartAt;
  DateTime? dartCompleteAt;
  DateTime? streamSelectedAt;
  DateTime? playerSetUrlStartAt;
  DateTime? playerReadyAt;
  DateTime? firstAudioPlayedAt;
  DateTime? failedAt;

  String? networkType;
  String? resolverUsed;
  String? codec;
  String? container;
  int? bitrate;
  String? errorReason;
  int? httpStatus;
  int retryCount = 0;
  bool wasCached = false;

  PlaybackDiagnosticsSession({
    required this.sessionId,
    required this.stemId,
    required this.title,
    required this.artist,
    required this.sourceId,
    required this.tappedAt,
    String? platform,
    String? osVersion,
    String? deviceModel,
  })  : platform = platform ?? (kIsWeb ? 'Web' : Platform.operatingSystem),
        osVersion = osVersion ?? (kIsWeb ? 'Browser' : Platform.operatingSystemVersion),
        deviceModel = deviceModel ?? (kIsWeb ? 'Web' : Platform.localHostname);

  // Latency Computations (in milliseconds)
  int? get tapToFirstAudioMs {
    if (firstAudioPlayedAt == null) return null;
    return firstAudioPlayedAt!.difference(tappedAt).inMilliseconds;
  }

  int? get tapToResolutionMs {
    if (streamSelectedAt == null) return null;
    return streamSelectedAt!.difference(tappedAt).inMilliseconds;
  }

  int? get resolutionToPlayerReadyMs {
    if (streamSelectedAt == null || playerReadyAt == null) return null;
    return playerReadyAt!.difference(streamSelectedAt!).inMilliseconds;
  }

  int? get playerReadyToFirstAudioMs {
    if (playerReadyAt == null || firstAudioPlayedAt == null) return null;
    return firstAudioPlayedAt!.difference(playerReadyAt!).inMilliseconds;
  }

  int? get nativeExtractionMs {
    if (nativeStartAt == null || nativeCompleteAt == null) return null;
    return nativeCompleteAt!.difference(nativeStartAt!).inMilliseconds;
  }

  int? get dartExtractionMs {
    if (dartStartAt == null || dartCompleteAt == null) return null;
    return dartCompleteAt!.difference(dartStartAt!).inMilliseconds;
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'stemId': stemId,
        'title': title,
        'artist': artist,
        'sourceId': sourceId,
        'platform': platform,
        'osVersion': osVersion,
        'deviceModel': deviceModel,
        'networkType': networkType,
        'resolverUsed': resolverUsed,
        'codec': codec,
        'container': container,
        'bitrate': bitrate,
        'wasCached': wasCached,
        'retryCount': retryCount,
        'tappedAt': tappedAt.toIso8601String(),
        'firstAudioPlayedAt': firstAudioPlayedAt?.toIso8601String(),
        'tapToFirstAudioMs': tapToFirstAudioMs,
        'tapToResolutionMs': tapToResolutionMs,
        'resolutionToPlayerReadyMs': resolutionToPlayerReadyMs,
        'playerReadyToFirstAudioMs': playerReadyToFirstAudioMs,
        'nativeExtractionMs': nativeExtractionMs,
        'dartExtractionMs': dartExtractionMs,
        'errorReason': errorReason,
        'httpStatus': httpStatus,
      };
}

class PlaybackDiagnosticsService {
  static final PlaybackDiagnosticsService _instance = PlaybackDiagnosticsService._internal();
  factory PlaybackDiagnosticsService() => _instance;
  PlaybackDiagnosticsService._internal();

  static const int maxStoredSessions = 50;
  final DoubleLinkedQueue<PlaybackDiagnosticsSession> _sessions = DoubleLinkedQueue();
  PlaybackDiagnosticsSession? _currentSession;

  PlaybackDiagnosticsSession? get currentSession => _currentSession;
  List<PlaybackDiagnosticsSession> get recentSessions => _sessions.toList().reversed.toList();

  PlaybackDiagnosticsSession startSession({
    required String stemId,
    required String title,
    required String artist,
    required String sourceId,
  }) {
    final session = PlaybackDiagnosticsSession(
      sessionId: 'diag_${DateTime.now().millisecondsSinceEpoch}_${stemId.hashCode.abs().toRadixString(16)}',
      stemId: stemId,
      title: title,
      artist: artist,
      sourceId: sourceId,
      tappedAt: DateTime.now(),
    );

    _currentSession = session;
    _sessions.addLast(session);
    while (_sessions.length > maxStoredSessions) {
      _sessions.removeFirst();
    }

    debugPrint('[Diagnostics] ⏱️ Started playback session: ${session.sessionId} for "$title"');
    return session;
  }

  void markMetadataAvailable(String sessionId) {
    _find(sessionId)?.metadataAvailableAt = DateTime.now();
  }

  void markSearchToYouTubeResolution(String sessionId) {
    _find(sessionId)?.searchToYouTubeResolutionAt = DateTime.now();
  }

  void markNativeStart(String sessionId) {
    _find(sessionId)?.nativeStartAt = DateTime.now();
  }

  void markNativeComplete(String sessionId) {
    _find(sessionId)?.nativeCompleteAt = DateTime.now();
  }

  void markDartStart(String sessionId) {
    _find(sessionId)?.dartStartAt = DateTime.now();
  }

  void markDartComplete(String sessionId) {
    _find(sessionId)?.dartCompleteAt = DateTime.now();
  }

  void markStreamSelected(
    String sessionId, {
    required String resolver,
    String? codec,
    String? container,
    int? bitrate,
    bool wasCached = false,
  }) {
    final s = _find(sessionId);
    if (s != null) {
      s.streamSelectedAt = DateTime.now();
      s.resolverUsed = resolver;
      s.codec = codec;
      s.container = container;
      s.bitrate = bitrate;
      s.wasCached = wasCached;
      debugPrint('[Diagnostics] 🎯 Stream selected via $resolver in ${s.tapToResolutionMs}ms (cached: $wasCached)');
    }
  }

  void markPlayerSetUrlStart(String sessionId) {
    _find(sessionId)?.playerSetUrlStartAt = DateTime.now();
  }

  void markPlayerReady(String sessionId) {
    final s = _find(sessionId);
    if (s != null) {
      s.playerReadyAt = DateTime.now();
    }
  }

  void markFirstAudioPlayed(String sessionId) {
    final s = _find(sessionId);
    if (s != null && s.firstAudioPlayedAt == null) {
      s.firstAudioPlayedAt = DateTime.now();
      debugPrint('[Diagnostics] 🔊 First audible audio for "${s.title}": ${s.tapToFirstAudioMs}ms total (resolution: ${s.tapToResolutionMs}ms, player: ${s.resolutionToPlayerReadyMs}ms)');
    }
  }

  void markError(String sessionId, {required String reason, int? httpStatus}) {
    final s = _find(sessionId);
    if (s != null) {
      s.failedAt = DateTime.now();
      s.errorReason = reason;
      s.httpStatus = httpStatus;
      debugPrint('[Diagnostics] ⚠️ Playback failure in ${s.sessionId}: $reason (HTTP: $httpStatus)');
    }
  }

  void markRetry(String sessionId) {
    final s = _find(sessionId);
    if (s != null) {
      s.retryCount++;
    }
  }

  PlaybackDiagnosticsSession? _find(String sessionId) {
    if (_currentSession?.sessionId == sessionId) return _currentSession;
    for (final s in _sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }

  String exportJson() {
    return jsonEncode(_sessions.map((s) => s.toJson()).toList());
  }

  void clear() {
    _sessions.clear();
    _currentSession = null;
  }
}
