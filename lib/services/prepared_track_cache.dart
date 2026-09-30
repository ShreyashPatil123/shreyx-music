import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/stem.dart';

class PreparedTrack {
  final String videoId;
  final String uri;
  final String codec;
  final String container;
  final int bitrate;
  final DateTime expiresAt;
  final DateTime resolvedAt;
  final String? userAgent;
  final Stem? effectiveStem;
  final String resolver;
  final String fileExtension;

  PreparedTrack({
    required this.videoId,
    required this.uri,
    required this.codec,
    required this.container,
    required this.bitrate,
    required this.expiresAt,
    required this.resolvedAt,
    required this.resolver,
    required this.fileExtension,
    this.userAgent,
    this.effectiveStem,
  });

  /// The configured lifetime is treated as a safety ceiling, not as absolute proof
  /// that YouTube's CDN has not already rotated or expired the token.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Approximate age of this resolved stream in seconds.
  int get ageSeconds => DateTime.now().difference(resolvedAt).inSeconds;
}

/// In-memory cache for prepared/resolved audio streams with dynamic revalidation
/// and immediate invalidation on 403/playback errors.
class PreparedTrackCache {
  static final PreparedTrackCache _instance = PreparedTrackCache._internal();
  factory PreparedTrackCache() => _instance;
  PreparedTrackCache._internal();

  /// Maximum cached streams in memory
  static const int maxEntries = 40;

  /// Absolute maximum safety ceiling for a YouTube CDN URL (even if the manifest claims longer)
  static const Duration maxCacheCeiling = Duration(hours: 3);

  final Map<String, PreparedTrack> _cache = LinkedHashMap();

  /// Retrieves an unexpired [PreparedTrack] for [videoId], or null if missing or expired.
  PreparedTrack? get(String videoId) {
    if (videoId.isEmpty) return null;
    final track = _cache[videoId];
    if (track == null) return null;

    if (track.isExpired) {
      debugPrint('[PreparedTrackCache] ⏰ Purging expired stream entry for $videoId (age: ${track.ageSeconds}s)');
      _cache.remove(videoId);
      return null;
    }

    // Refresh LRU position
    _cache.remove(videoId);
    _cache[videoId] = track;
    return track;
  }

  /// Inserts a newly resolved [PreparedTrack] into the cache.
  void put(PreparedTrack track) {
    if (track.videoId.isEmpty || track.uri.isEmpty) return;

    // Clamp expiry to safety ceiling
    final maxExpiry = DateTime.now().add(maxCacheCeiling);
    final effectiveExpiry = track.expiresAt.isBefore(maxExpiry) ? track.expiresAt : maxExpiry;

    final clampedTrack = PreparedTrack(
      videoId: track.videoId,
      uri: track.uri,
      codec: track.codec,
      container: track.container,
      bitrate: track.bitrate,
      expiresAt: effectiveExpiry,
      resolvedAt: track.resolvedAt,
      resolver: track.resolver,
      fileExtension: track.fileExtension,
      userAgent: track.userAgent,
      effectiveStem: track.effectiveStem,
    );

    _cache.remove(track.videoId);
    _cache[track.videoId] = clampedTrack;

    // Prune LRU overflow
    while (_cache.length > maxEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    debugPrint('[PreparedTrackCache] 💾 Cached stream for ${track.videoId} via ${track.resolver} (expires in ${effectiveExpiry.difference(DateTime.now()).inMinutes}m)');
  }

  /// Deterministically invalidates and purges the cached stream for [videoId].
  ///
  /// MUST be invoked whenever the player reports an HTTP 403, forbidden, expired,
  /// or unplayable stream error, ensuring retries never reuse the stale URL.
  void invalidate(String videoId) {
    if (videoId.isEmpty) return;
    if (_cache.remove(videoId) != null) {
      debugPrint('[PreparedTrackCache] 🚫 Invalidation: Evicted stale/failed stream for $videoId');
    }
  }

  /// Cleans all expired entries.
  void purgeExpired() {
    _cache.removeWhere((id, track) => track.isExpired);
  }

  /// Clears the entire in-memory stream cache.
  void clear() {
    _cache.clear();
    debugPrint('[PreparedTrackCache] 🧹 Cache cleared');
  }

  int get size => _cache.length;
}
