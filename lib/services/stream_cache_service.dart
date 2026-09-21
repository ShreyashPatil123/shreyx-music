import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fast_downloader.dart';

/// Zero-touch LRU audio cache.
///
/// Every song that streams from the network is silently saved to disk.
/// On repeat play the cached file is used directly — 0ms latency, zero
/// internet usage. Least-recently-played tracks are evicted when the
/// cache exceeds [maxCacheBytes] (~512 MB ≈ 125 tracks at 4 MB each).
class StreamCacheService {
  static final StreamCacheService _instance = StreamCacheService._internal();
  factory StreamCacheService() => _instance;
  StreamCacheService._internal();

  static const String _metaKey = 'shrex_stream_cache_meta';

  /// Rolling cap — 512 MB keeps ~125 tracks cached.
  static const int maxCacheBytes = 512 * 1024 * 1024;

  late Directory _cacheDir;
  bool _ready = false;

  /// { stemId → CacheEntry }
  final Map<String, CacheEntry> _entries = {};

  // ───────────────────── init ─────────────────────

  Future<void> init() async {
    if (_ready) return;
    final appCache = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appCache.path}/stream_cache');
    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
    }
    await _loadMeta();
    // Prune stale entries whose file was deleted externally
    _entries.removeWhere((_, e) => !File(e.filePath).existsSync());
    await _saveMeta();
    _ready = true;
    debugPrint('[StreamCache] init  dir=${_cacheDir.path}  '
        'entries=${_entries.length}  size=${_totalBytes()}');
  }

  // ───────────────── public API ──────────────────

  /// Returns the cached file path for [stemId], or null.
  /// Also bumps its `lastPlayedAt` so the LRU knows it's fresh.
  String? getCachedPath(String stemId) {
    final entry = _entries[stemId];
    if (entry == null) return null;
    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _entries.remove(stemId);
      _saveMeta(); // fire-and-forget
      return null;
    }
    // Touch LRU timestamp
    _entries[stemId] = entry.copyWith(
      lastPlayedAt: DateTime.now(),
    );
    _saveMeta(); // fire-and-forget
    return entry.filePath;
  }

  /// Returns the cached File object for [stemId], or null if not cached.
  File? getCachedFile(String stemId) {
    final path = getCachedPath(stemId);
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// The file path where a new cache file for [stemId] should be written.
  String cacheFilePath(String stemId) {
    return '${_cacheDir.path}/$stemId.m4a';
  }

  /// Register a completed download into the LRU index.
  Future<void> registerCachedFile({
    required String stemId,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) return;
    final sizeBytes = file.lengthSync();

    _entries[stemId] = CacheEntry(
      stemId: stemId,
      filePath: filePath,
      sizeBytes: sizeBytes,
      lastPlayedAt: DateTime.now(),
    );

    // Evict LRU if over budget
    await _evictIfNeeded();
    await _saveMeta();
    debugPrint('[StreamCache] cached $stemId  '
        '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB  '
        'total=${(_totalBytes() / 1024 / 1024).toStringAsFixed(0)} MB');
  }

  /// Downloads the audio from [url] to a local cache file in the background.
  /// Returns the local file path on success, null on failure.
  /// This runs silently — it doesn't block playback.
  Future<String?> backgroundCacheStream({
    required String stemId,
    required String url,
    String? userAgent,
  }) async {
    // Don't re-download if already cached
    if (_entries.containsKey(stemId) && File(_entries[stemId]!.filePath).existsSync()) {
      return _entries[stemId]!.filePath;
    }

    final filePath = cacheFilePath(stemId);
    final tmpPath = '$filePath.tmp';

    try {
      await FastDownloader.download(
        url: url,
        destinationPath: tmpPath,
        userAgent: userAgent,
        concurrency: 3,
        chunkSize: 1024 * 1024,
      );

      // Rename atomically
      await File(tmpPath).rename(filePath);

      await registerCachedFile(stemId: stemId, filePath: filePath);
      return filePath;
    } catch (e) {
      debugPrint('[StreamCache] bg-cache error for $stemId: $e');
      // Clean up partial file
      try { File(tmpPath).deleteSync(); } catch (_) {}
      return null;
    }
  }

  /// Total bytes currently in cache.
  int get totalCacheBytes => _totalBytes();

  /// Number of cached tracks.
  int get entryCount => _entries.length;

  // ───────────────── internals ───────────────────

  int _totalBytes() =>
      _entries.values.fold<int>(0, (sum, e) => sum + e.sizeBytes);

  Future<void> _evictIfNeeded() async {
    while (_totalBytes() > maxCacheBytes && _entries.isNotEmpty) {
      // Find oldest entry
      final oldest = _entries.values.reduce(
          (a, b) => a.lastPlayedAt.isBefore(b.lastPlayedAt) ? a : b);
      try {
        File(oldest.filePath).deleteSync();
      } catch (_) {}
      _entries.remove(oldest.stemId);
      debugPrint('[StreamCache] evicted ${oldest.stemId}');
    }
  }

  Future<void> _loadMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_metaKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final entry = CacheEntry.fromJson(item as Map<String, dynamic>);
        _entries[entry.stemId] = entry;
      }
    } catch (e) {
      debugPrint('[StreamCache] loadMeta error: $e');
    }
  }

  Future<void> _saveMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _entries.values.map((e) => e.toJson()).toList();
      await prefs.setString(_metaKey, jsonEncode(jsonList));
    } catch (_) {}
  }
}

// ─────────────────── CacheEntry model ───────────────────

class CacheEntry {
  final String stemId;
  final String filePath;
  final int sizeBytes;
  final DateTime lastPlayedAt;

  const CacheEntry({
    required this.stemId,
    required this.filePath,
    required this.sizeBytes,
    required this.lastPlayedAt,
  });

  CacheEntry copyWith({DateTime? lastPlayedAt}) => CacheEntry(
        stemId: stemId,
        filePath: filePath,
        sizeBytes: sizeBytes,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      );

  Map<String, dynamic> toJson() => {
        'stemId': stemId,
        'filePath': filePath,
        'sizeBytes': sizeBytes,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        stemId: json['stemId'] as String,
        filePath: json['filePath'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      );
}
