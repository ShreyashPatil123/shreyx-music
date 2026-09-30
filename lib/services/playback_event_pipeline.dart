import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stem.dart';

class PlaybackHistoryItem {
  final String sessionId;
  final String stemId;
  final String title;
  final String artist;
  final String artworkUrl;
  final String sourceId;
  final String playbackSource; // e.g. 'search', 'playlist', 'vault', 'radio'
  final DateTime startedAt;
  DateTime? completedAt;
  int listenedDurationSec;
  double completionPercentage;
  final Map<String, dynamic> rawStemJson;

  PlaybackHistoryItem({
    required this.sessionId,
    required this.stemId,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.sourceId,
    required this.playbackSource,
    required this.startedAt,
    this.completedAt,
    this.listenedDurationSec = 0,
    this.completionPercentage = 0.0,
    required this.rawStemJson,
  });

  Stem get stem => Stem.fromJson(rawStemJson);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'stemId': stemId,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'sourceId': sourceId,
        'playbackSource': playbackSource,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'listenedDurationSec': listenedDurationSec,
        'completionPercentage': completionPercentage,
        'rawStemJson': rawStemJson,
      };

  factory PlaybackHistoryItem.fromJson(Map<String, dynamic> json) => PlaybackHistoryItem(
        sessionId: json['sessionId'] as String? ?? '',
        stemId: json['stemId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String? ?? '',
        sourceId: json['sourceId'] as String? ?? '',
        playbackSource: json['playbackSource'] as String? ?? 'unknown',
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
        completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
        listenedDurationSec: (json['listenedDurationSec'] as num?)?.toInt() ?? 0,
        completionPercentage: (json['completionPercentage'] as num?)?.toDouble() ?? 0.0,
        rawStemJson: json['rawStemJson'] as Map<String, dynamic>? ?? {},
      );
}

/// Deterministic playback event pipeline and rich local history engine.
///
/// Ensures only one history record is created per playback session, regardless of
/// stream retries, crossfade swaps, or UI rebuilds.
class PlaybackEventPipeline {
  static final PlaybackEventPipeline _instance = PlaybackEventPipeline._internal();
  factory PlaybackEventPipeline() => _instance;
  PlaybackEventPipeline._internal();

  static const String _storageKey = 'shrex_rich_playback_history_v2';
  static const String _playCountsKey = 'shrex_play_counts_v2';
  static const int maxStoredHistory = 250;

  final List<PlaybackHistoryItem> _history = [];
  final Map<String, int> _playCounts = {};
  final Set<String> _recordedSessionIds = {};

  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;
  PlaybackHistoryItem? _activeItem;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHistory = prefs.getString(_storageKey);
      if (rawHistory != null) {
        final list = jsonDecode(rawHistory) as List<dynamic>;
        _history.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _history.add(PlaybackHistoryItem.fromJson(item));
          }
        }
      }

      final rawCounts = prefs.getString(_playCountsKey);
      if (rawCounts != null) {
        final map = jsonDecode(rawCounts) as Map<String, dynamic>;
        _playCounts.clear();
        for (final key in map.keys) {
          _playCounts[key] = (map[key] as num).toInt();
        }
      }
    } catch (e) {
      debugPrint('[PlaybackEventPipeline] init error: $e');
    }
  }

  /// Event 1: User requested track playback.
  void onPlayRequested(Stem stem, {String source = 'unknown', required String sessionId}) {
    _currentSessionId = sessionId;
  }

  /// Event 2: Actual audio playback started.
  ///
  /// Guarantees that only ONE history entry is created for this [sessionId].
  Future<void> onPlayStarted(Stem stem, {required String sessionId, String source = 'app'}) async {
    if (_recordedSessionIds.contains(sessionId)) {
      // Duplicate prevention: Session already recorded
      return;
    }
    _recordedSessionIds.add(sessionId);

    // Remove older duplicate entry for the same stem to bring to top of Recently Played
    _history.removeWhere((item) => item.stemId == stem.id);

    final item = PlaybackHistoryItem(
      sessionId: sessionId,
      stemId: stem.id,
      title: stem.title,
      artist: stem.artistName,
      artworkUrl: stem.artworkUrl,
      sourceId: stem.sourceId,
      playbackSource: source,
      startedAt: DateTime.now(),
      rawStemJson: stem.toJson(),
    );

    _activeItem = item;
    _history.insert(0, item);
    while (_history.length > maxStoredHistory) {
      _history.removeLast();
    }

    _playCounts[stem.id] = (_playCounts[stem.id] ?? 0) + 1;

    await _save();
    debugPrint('[PlaybackEventPipeline] 📝 Registered playback for "${stem.title}" (play count: ${_playCounts[stem.id]})');
  }

  /// Event 3: Playback position progress update.
  void onPlayProgress({required String sessionId, required Duration position, required Duration total}) {
    if (_activeItem != null && _activeItem!.sessionId == sessionId && total.inSeconds > 0) {
      _activeItem!.listenedDurationSec = position.inSeconds;
      _activeItem!.completionPercentage = (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    }
  }

  /// Event 4: Track completed playing through.
  Future<void> onPlayCompleted({required String sessionId}) async {
    if (_activeItem != null && _activeItem!.sessionId == sessionId) {
      _activeItem!.completedAt = DateTime.now();
      _activeItem!.completionPercentage = 1.0;
      await _save();
    }
  }

  /// Event 5: User skipped track.
  Future<void> onPlaySkipped({required String sessionId}) async {
    if (_activeItem != null && _activeItem!.sessionId == sessionId) {
      _activeItem!.completedAt = DateTime.now();
      await _save();
    }
  }

  /// Exposes: Recently Played tracks.
  List<Stem> getRecentlyPlayed({int limit = 30}) {
    return _history.map((h) => h.stem).take(limit).toList();
  }

  /// Exposes: Continue Listening (tracks paused between 10% and 90% completion).
  List<Stem> getContinueListening({int limit = 15}) {
    return _history
        .where((h) => h.completionPercentage >= 0.1 && h.completionPercentage <= 0.9)
        .map((h) => h.stem)
        .take(limit)
        .toList();
  }

  /// Exposes: Most Played tracks sorted by lifetime play counts.
  List<Stem> getMostPlayed({int limit = 20}) {
    final Map<String, Stem> stemsMap = {};
    for (final h in _history) {
      stemsMap[h.stemId] = h.stem;
    }

    final sortedIds = _playCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<Stem> result = [];
    for (final entry in sortedIds) {
      if (stemsMap.containsKey(entry.key)) {
        result.add(stemsMap[entry.key]!);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  int getPlayCount(String stemId) => _playCounts[stemId] ?? 0;

  Future<void> clearHistory() async {
    _history.clear();
    _playCounts.clear();
    _recordedSessionIds.clear();
    _activeItem = null;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_history.map((h) => h.toJson()).toList()));
      await prefs.setString(_playCountsKey, jsonEncode(_playCounts));
    } catch (_) {}
  }
}
