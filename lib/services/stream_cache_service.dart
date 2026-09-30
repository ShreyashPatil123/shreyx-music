import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fast_downloader.dart';

/// Zero-touch LRU audio cache with exact container/codec format integrity.
///
/// Ensures tracks are saved with extensions matching their actual media
/// representation (.webm for WebM/Opus, .m4a for AAC/MP4).
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
    debugPrint('[StreamCache] init dir=${_cacheDir.path} entries=${_entries.length} size=${_totalBytes()}');
  }

  /// Returns the cached file path for [stemId], or null.
  /// Also bumps its `lastPlayedAt` so the LRU knows it's fresh.
  String? getCachedPath(String stemId) {
    var entry = _entries[stemId];

    // Fallback: check disk for webm or m4a if not in memory index
    if (entry == null) {
      final webm = File('${_cacheDir.path}/$stemId.webm');
      final m4a = File('${_cacheDir.path}/$stemId.m4a');
      if (webm.existsSync() && webm.lengthSync() > 0) {
        registerCachedFile(stemId: stemId, filePath: webm.path);
        entry = _entries[stemId];
      } else if (m4a.existsSync() && m4a.lengthSync() > 0) {
        registerCachedFile(stemId: stemId, filePath: m4a.path);
        entry = _entries[stemId];
      }
    }

    if (entry == null) return null;
    final file = File(entry.filePath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      _entries.remove(stemId);
      _saveMeta();
      return null;
    }

    // Touch LRU timestamp
    _entries[stemId] = entry.copyWith(
      lastPlayedAt: DateTime.now(),
    );
    _saveMeta();
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
  String cacheFilePath(String stemId, {String? container}) {
    final c = (container ?? '').toLowerCase();
    final ext = c.contains('webm') || c.contains('opus') ? 'webm' : 'm4a';
    return '${_cacheDir.path}/$stemId.$ext';
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
    debugPrint('[StreamCache] cached $stemId ${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');
  }

  /// Downloads the audio from [url] to a local cache file in the background.
  /// Runs with reduced concurrency (2 workers) to prevent competing with active playback (Point 9).
  Future<String?> backgroundCacheStream({
    required String stemId,
    required String url,
    String? userAgent,
    String? container,
  }) async {
    // Don't re-download if already cached
    final existing = getCachedPath(stemId);
    if (existing != null) return existing;

    final filePath = cacheFilePath(stemId, container: container);
    final tmpPath = '$filePath.tmp';

    try {
      await FastDownloader.download(
        url: url,
        destinationPath: tmpPath,
        userAgent: userAgent,
        concurrency: 2, // Controlled concurrency to prevent playback starvation
        chunkSize: 1024 * 1024,
      );

      // Rename atomically
      await File(tmpPath).rename(filePath);

      await registerCachedFile(stemId: stemId, filePath: filePath);
      return filePath;
    } catch (e) {
      debugPrint('[StreamCache] bg-cache error for $stemId: $e');
      try {
        File(tmpPath).deleteSync();
      } catch (_) {}
      return null;
    }
  }

  int get totalCacheBytes => _totalBytes();
  int get entryCount => _entries.length;

  Future<void> clearCache() async {
    for (final entry in _entries.values.toList()) {
      try {
        final file = File(entry.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _entries.clear();
    await _saveMeta();
    debugPrint('[StreamCache] Cache cleared');
  }

  int _totalBytes() => _entries.values.fold<int>(0, (sum, e) => sum + e.sizeBytes);

  Future<void> _evictIfNeeded() async {
    while (_totalBytes() > maxCacheBytes && _entries.isNotEmpty) {
      final oldest = _entries.values.reduce(
        (a, b) => a.lastPlayedAt.isBefore(b.lastPlayedAt) ? a : b,
      );
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

class CacheEntry {
  final String stemId;
  final String filePath;
  final int sizeBytes;
  final DateTime lastPlayedAt;

  CacheEntry({
    required this.stemId,
    required this.filePath,
    required this.sizeBytes,
    required this.lastPlayedAt,
  });

  CacheEntry copyWith({
    String? stemId,
    String? filePath,
    int? sizeBytes,
    DateTime? lastPlayedAt,
  }) {
    return CacheEntry(
      stemId: stemId ?? this.stemId,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'stemId': stemId,
        'filePath': filePath,
        'sizeBytes': sizeBytes,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        stemId: json['stemId'] as String,
        filePath: json['filePath'] as String,
        sizeBytes: json['sizeBytes'] as int,
        lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      );
}
