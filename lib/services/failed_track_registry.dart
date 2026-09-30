import 'package:flutter/foundation.dart';

class TrackFailureRecord {
  final String videoId;
  final String reason;
  final DateTime lastAttempt;
  final int attemptCount;

  TrackFailureRecord({
    required this.videoId,
    required this.reason,
    required this.lastAttempt,
    required this.attemptCount,
  });

  TrackFailureRecord increment(String newReason) => TrackFailureRecord(
        videoId: videoId,
        reason: newReason,
        lastAttempt: DateTime.now(),
        attemptCount: attemptCount + 1,
      );
}

/// In-memory registry tracking failed or unplayable tracks with exponential backoff.
class FailedTrackRegistry {
  static final FailedTrackRegistry _instance = FailedTrackRegistry._internal();
  factory FailedTrackRegistry() => _instance;
  FailedTrackRegistry._internal();

  /// Cooldown window before a persistently failing track may be re-attempted automatically.
  static const Duration cooldownPeriod = Duration(minutes: 5);

  final Map<String, TrackFailureRecord> _records = {};

  /// Checks if [videoId] is currently suppressed due to recent repeated failures.
  bool isBlocked(String videoId) {
    final record = _records[videoId];
    if (record == null) return false;

    final elapsed = DateTime.now().difference(record.lastAttempt);
    if (elapsed > cooldownPeriod) {
      _records.remove(videoId);
      return false;
    }

    return record.attemptCount >= 2;
  }

  /// Records a playback or resolution failure for [videoId].
  void recordFailure(String videoId, String reason) {
    if (videoId.isEmpty) return;
    final existing = _records[videoId];
    if (existing == null) {
      _records[videoId] = TrackFailureRecord(
        videoId: videoId,
        reason: reason,
        lastAttempt: DateTime.now(),
        attemptCount: 1,
      );
    } else {
      _records[videoId] = existing.increment(reason);
    }
    debugPrint('[FailedTrackRegistry] ⚠️ Track $videoId recorded failure (count: ${_records[videoId]!.attemptCount}): $reason');
  }

  /// Clears any failure record for [videoId] (e.g. after manual user play or successful resolution).
  void clearFailure(String videoId) {
    _records.remove(videoId);
  }

  void clearAll() {
    _records.clear();
  }
}
