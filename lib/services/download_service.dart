import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/stem.dart';
import 'fast_downloader.dart';
import 'stream_cache_service.dart';
import 'stream_resolver.dart';

class DownloadProgress {
  final String stemId;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final String? error;

  DownloadProgress({
    required this.stemId,
    required this.progress,
    this.isCompleted = false,
    this.error,
  });
}

class ActiveDownload {
  final Stem stem;
  final String? playlistId;
  final String? playlistTitle;
  final String? playlistArtwork;
  double progress; // 0.0 to 1.0
  String status; // 'resolving', 'downloading', 'completed', 'error'
  String? error;

  ActiveDownload({
    required this.stem,
    this.playlistId,
    this.playlistTitle,
    this.playlistArtwork,
    this.progress = 0.0,
    this.status = 'resolving',
    this.error,
  });
}

class ActivePlaylistDownload {
  final String playlistId;
  final String title;
  final String artworkUrl;
  final int totalCount;
  int completedCount;
  double currentSongProgress;
  String currentSongTitle;

  ActivePlaylistDownload({
    required this.playlistId,
    required this.title,
    required this.artworkUrl,
    required this.totalCount,
    this.completedCount = 0,
    this.currentSongProgress = 0.0,
    this.currentSongTitle = '',
  });

  double get overallProgress {
    if (totalCount == 0) return 1.0;
    return ((completedCount + currentSongProgress) / totalCount).clamp(0.0, 1.0);
  }
}

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final StreamResolver _resolver = StreamResolver();
  final StreamCacheService _streamCache = StreamCacheService();

  final Map<String, Stem> _downloads = {};
  final Map<String, ActiveDownload> _activeDownloads = {};
  final Map<String, ActivePlaylistDownload> _activePlaylists = {};
  final Map<String, bool> _cancelTokens = {};

  final _progressController = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  static const String _prefKey = 'shrex_downloaded_stems';

  Future<void> init() async {
    await _streamCache.init();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final stem = Stem.fromJson(item as Map<String, dynamic>);
          // Verify file still exists on device
          if (stem.localFilePath != null && File(stem.localFilePath!).existsSync()) {
            _downloads[stem.id] = stem;
          }
        }
      } catch (_) {}
    }
  }

  bool isDownloaded(String stemId) => _downloads.containsKey(stemId);
  bool isDownloading(String stemId) => _activeDownloads.containsKey(stemId);
  bool isPlaylistDownloading(String playlistId) => _activePlaylists.containsKey(playlistId);

  double getProgress(String stemId) => _activeDownloads[stemId]?.progress ?? 0.0;
  double getPlaylistProgress(String playlistId) =>
      _activePlaylists[playlistId]?.overallProgress ?? 0.0;

  List<Stem> getAllDownloads() => _downloads.values.toList();
  List<ActiveDownload> get activeDownloads => _activeDownloads.values.toList();
  List<ActivePlaylistDownload> get activePlaylists => _activePlaylists.values.toList();

  Future<String> _getDownloadDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${docsDir.path}/shrex_downloads');
    if (!downloadDir.existsSync()) {
      downloadDir.createSync(recursive: true);
    }
    return downloadDir.path;
  }

  Future<void> downloadStem(
    Stem stem, {
    String? playlistId,
    String? playlistTitle,
    String? playlistArtwork,
  }) async {
    if (isDownloaded(stem.id) || isDownloading(stem.id)) return;

    final activeItem = ActiveDownload(
      stem: stem,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
      playlistArtwork: playlistArtwork,
      progress: 0.0,
      status: 'resolving',
    );
    _activeDownloads[stem.id] = activeItem;
    _cancelTokens[stem.id] = false;
    _progressController.add(DownloadProgress(stemId: stem.id, progress: 0.0));

    try {
      final downloadDir = await _getDownloadDir();
      final filePath = '$downloadDir/${stem.id}.m4a';
      final file = File(filePath);

      // ── Step 1: Check StreamCacheService (instant copy if already auto-cached) ──
      final cachedFile = _streamCache.getCachedFile(stem.id);
      if (cachedFile != null && cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
        debugPrint('[DownloadService] ⚡ Instant copy from local cache for "${stem.title}"');
        await cachedFile.copy(filePath);
        final fileSize = file.lengthSync();

        final targetPlaylistId = playlistId ?? 'standalone';
        final targetPlaylistTitle = playlistTitle ?? 'Standalone Tracks';
        final targetPlaylistArt = playlistArtwork ?? stem.artworkUrl;

        final downloadedStem = stem.copyWith(
          localFilePath: filePath,
          fileSizeBytes: fileSize,
          playlistId: targetPlaylistId,
          playlistTitle: targetPlaylistTitle,
          playlistArtwork: targetPlaylistArt,
        );

        _downloads[stem.id] = downloadedStem;
        _activeDownloads.remove(stem.id);
        _cancelTokens.remove(stem.id);
        await _save();

        _progressController.add(
          DownloadProgress(stemId: stem.id, progress: 1.0, isCompleted: true),
        );
        return;
      }

      // ── Step 2: Resolve stream URL (uses Native NewPipe on Android) ──
      activeItem.status = 'resolving';
      _progressController.add(DownloadProgress(stemId: stem.id, progress: 0.05));

      final resolved = await _resolver.resolveStream(stem);
      if (_cancelTokens[stem.id] == true) throw Exception('Download cancelled by user');

      activeItem.status = 'downloading';
      activeItem.progress = 0.1;
      _progressController.add(DownloadProgress(stemId: stem.id, progress: 0.1));

      // ── Step 3: High-speed parallel Range download via FastDownloader ──
      debugPrint('[DownloadService] 🚀 Starting high-speed parallel download for "${stem.title}"...');
      final receivedBytes = await FastDownloader.download(
        url: resolved.url,
        destinationPath: filePath,
        userAgent: resolved.userAgent,
        chunkSize: 1024 * 1024, // 1MB chunks to hit unthrottled burst bandwidth
        concurrency: 3,         // 3 parallel Range workers
        isCancelled: () => _cancelTokens[stem.id] == true,
        onProgress: (prog, received, total) {
          activeItem.progress = prog;
          _progressController.add(DownloadProgress(stemId: stem.id, progress: prog));
        },
      );

      final targetPlaylistId = playlistId ?? 'standalone';
      final targetPlaylistTitle = playlistTitle ?? 'Standalone Tracks';
      final targetPlaylistArt = playlistArtwork ?? stem.artworkUrl;

      final downloadedStem = stem.copyWith(
        localFilePath: filePath,
        fileSizeBytes: receivedBytes,
        playlistId: targetPlaylistId,
        playlistTitle: targetPlaylistTitle,
        playlistArtwork: targetPlaylistArt,
      );

      _downloads[stem.id] = downloadedStem;
      _activeDownloads.remove(stem.id);
      _cancelTokens.remove(stem.id);
      await _save();

      // Register file so local streaming immediately hits it
      await _streamCache.registerCachedFile(stemId: stem.id, filePath: filePath);

      _progressController.add(
        DownloadProgress(stemId: stem.id, progress: 1.0, isCompleted: true),
      );
      debugPrint('[DownloadService] ✅ Download complete: "${stem.title}" ($receivedBytes bytes)');
    } catch (err) {
      _activeDownloads.remove(stem.id);
      _cancelTokens.remove(stem.id);
      _progressController.add(
        DownloadProgress(stemId: stem.id, progress: 0.0, error: err.toString()),
      );
      debugPrint('[DownloadService] ❌ Download error for "${stem.title}": $err');
    }
  }

  Future<void> downloadPlaylist(Playlist playlist) async {
    if (playlist.stems.isEmpty) return;

    final unDownloaded = playlist.stems.where((s) => !isDownloaded(s.id)).toList();
    if (unDownloaded.isEmpty) return;

    final activePlaylist = ActivePlaylistDownload(
      playlistId: playlist.id,
      title: playlist.name,
      artworkUrl: playlist.artworkUrl,
      totalCount: unDownloaded.length,
      completedCount: 0,
      currentSongProgress: 0.0,
      currentSongTitle: unDownloaded.first.title,
    );
    _activePlaylists[playlist.id] = activePlaylist;
    _cancelTokens[playlist.id] = false;
    _progressController.add(DownloadProgress(stemId: playlist.id, progress: 0.0));

    // Listen to child stem progress to calculate playlist-level progress
    final childSub = progressStream.listen((p) {
      if (_activePlaylists.containsKey(playlist.id)) {
        final currentActive = _activeDownloads[p.stemId];
        if (currentActive != null && currentActive.playlistId == playlist.id) {
          activePlaylist.currentSongProgress = p.progress;
          _progressController.add(
            DownloadProgress(stemId: playlist.id, progress: activePlaylist.overallProgress),
          );
        }
      }
    });

    try {
      for (int i = 0; i < unDownloaded.length; i++) {
        if (_cancelTokens[playlist.id] == true) break;
        final stem = unDownloaded[i];
        activePlaylist.currentSongTitle = stem.title;
        activePlaylist.currentSongProgress = 0.0;

        await downloadStem(
          stem,
          playlistId: playlist.id,
          playlistTitle: playlist.name,
          playlistArtwork: playlist.artworkUrl,
        );

        activePlaylist.completedCount = i + 1;
        activePlaylist.currentSongProgress = 0.0;
        _progressController.add(
          DownloadProgress(stemId: playlist.id, progress: activePlaylist.overallProgress),
        );
      }
    } finally {
      await childSub.cancel();
      _activePlaylists.remove(playlist.id);
      _cancelTokens.remove(playlist.id);
      _progressController.add(
        DownloadProgress(stemId: playlist.id, progress: 1.0, isCompleted: true),
      );
    }
  }

  void cancelDownload(String stemId) {
    _cancelTokens[stemId] = true;
    _activeDownloads.remove(stemId);
    _progressController.add(
      DownloadProgress(stemId: stemId, progress: 0.0, error: 'Cancelled'),
    );
  }

  void cancelPlaylistDownload(String playlistId) {
    _cancelTokens[playlistId] = true;
    _activePlaylists.remove(playlistId);
    _progressController.add(
      DownloadProgress(stemId: playlistId, progress: 0.0, error: 'Cancelled'),
    );
  }

  Future<void> removeDownload(String stemId) async {
    final item = _downloads[stemId];
    if (item?.localFilePath != null) {
      try {
        final f = File(item!.localFilePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _downloads.remove(stemId);
    await _save();
  }

  List<DownloadedPlaylistGroup> getGroupedDownloads() {
    final Map<String, List<Stem>> groups = {};

    for (final stem in _downloads.values) {
      final key = stem.playlistId ?? 'standalone';
      groups.putIfAbsent(key, () => []).add(stem);
    }

    final List<DownloadedPlaylistGroup> result = [];

    for (final entry in groups.entries) {
      final stems = entry.value;
      final isStandalone = entry.key == 'standalone';
      final first = stems.first;
      final title = isStandalone ? 'Standalone Tracks' : (first.playlistTitle ?? 'Playlist');
      final artwork = isStandalone
          ? (first.artworkUrl)
          : (first.playlistArtwork ?? first.artworkUrl);
      final totalSize = stems.fold<int>(0, (sum, s) => sum + (s.fileSizeBytes ?? 0));

      result.add(DownloadedPlaylistGroup(
        id: entry.key,
        title: title,
        artworkUrl: artwork,
        stems: stems,
        totalSizeBytes: totalSize,
        isStandalone: isStandalone,
      ));
    }

    // Sort: custom playlists first, Standalone at the bottom
    result.sort((a, b) {
      if (a.isStandalone && !b.isStandalone) return 1;
      if (!a.isStandalone && b.isStandalone) return -1;
      return a.title.compareTo(b.title);
    });

    return result;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _downloads.values.map((s) => s.toJson()).toList();
    await prefs.setString(_prefKey, jsonEncode(jsonList));
  }

  void dispose() {
    _progressController.close();
  }
}
