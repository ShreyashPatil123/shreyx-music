import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/playlist.dart';
import '../models/stem.dart';
import 'vault_service.dart';

class _PlaylistStreamSession {
  final String listId;
  final StreamIterator<Video> iterator;
  bool isExhausted;
  DateTime lastAccessed;

  _PlaylistStreamSession({
    required this.listId,
    required this.iterator,
  })  : isExhausted = false,
        lastAccessed = DateTime.now();

  Future<void> dispose() async {
    try {
      await iterator.cancel();
    } catch (_) {}
  }
}

/// Service managing infinite pagination and streaming for large playlists.
///
/// Removes the hardcoded ~100-song playlist ceiling by lazily loading
/// chunks of tracks on scroll and during audio queue replenishment.
class PlaylistPaginationService {
  static final PlaylistPaginationService _instance = PlaylistPaginationService._internal();
  factory PlaylistPaginationService() => _instance;
  PlaylistPaginationService._internal();

  final Map<String, _PlaylistStreamSession> _sessions = {};
  YoutubeExplode? _ytInstance;

  @visibleForTesting
  YoutubeExplode? customYtClient;

  YoutubeExplode get _yt => customYtClient ?? (_ytInstance ??= YoutubeExplode());

  /// Loads the initial batch of tracks for a YouTube playlist.
  ///
  /// Quickly returns the first [initialPageSize] tracks so UI and playback can start immediately,
  /// while caching the active stream session for subsequent pagination.
  Future<Playlist> loadInitialYouTubeBatch({
    required String listId,
    required String title,
    required String author,
    required String artworkUrl,
    int? totalVideoCount,
    int initialPageSize = 50,
  }) async {
    // Clean up any stale existing session for this playlist
    await _sessions[listId]?.dispose();
    _sessions.remove(listId);

    final videoStream = _yt.playlists.getVideos(listId);
    final iterator = StreamIterator(videoStream);
    final session = _PlaylistStreamSession(listId: listId, iterator: iterator);
    _sessions[listId] = session;

    final List<Stem> stems = [];
    final encounteredIds = <String>{};
    bool streamEnded = false;

    try {
      while (stems.length < initialPageSize) {
        final hasNext = await session.iterator.moveNext();
        if (!hasNext) {
          streamEnded = true;
          break;
        }

        final video = session.iterator.current;
        if (!encounteredIds.add(video.id.value)) continue;

        stems.add(Stem(
          id: 'yt_${video.id.value}',
          title: video.title,
          artistName: video.author,
          artworkUrl: video.thumbnails.standardResUrl.isNotEmpty
              ? video.thumbnails.standardResUrl
              : (video.thumbnails.highResUrl.isNotEmpty
                  ? video.thumbnails.highResUrl
                  : artworkUrl),
          durationSec: video.duration?.inSeconds ?? 0,
          sourceId: video.id.value,
          albumName: title,
          playlistId: 'pl_yt_$listId',
          playlistTitle: title,
          playlistArtwork: artworkUrl,
        ));
      }
    } catch (e) {
      debugPrint('[PlaylistPagination] Error loading initial batch for $listId: $e');
      if (stems.isEmpty) rethrow;
    }

    if (streamEnded) {
      session.isExhausted = true;
    }

    final bool hasMore = !session.isExhausted &&
        (totalVideoCount == null || stems.length < totalVideoCount);

    return Playlist(
      id: 'pl_yt_$listId',
      name: title,
      description: 'Imported YouTube playlist by $author${totalVideoCount != null ? ' ($totalVideoCount tracks)' : ''}',
      artworkUrl: artworkUrl,
      stems: stems,
      sourceId: listId,
      sourceType: 'youtube',
      sourceUrl: 'https://www.youtube.com/playlist?list=$listId',
      totalTrackCount: totalVideoCount,
      hasMore: hasMore,
    );
  }

  /// Loads the next page of tracks for [playlist].
  ///
  /// Incremental and deduplicated. Appends to [playlist.stems], updates [playlist.hasMore],
  /// and automatically updates the vault copy if it exists.
  Future<List<Stem>> loadNextPage(Playlist playlist, {int pageSize = 50}) async {
    if (!playlist.hasMore) {
      debugPrint('[PlaylistPagination] Playlist "${playlist.name}" is already fully loaded.');
      return [];
    }

    final listId = playlist.sourceId;
    if (listId == null || listId.isEmpty || playlist.sourceType != 'youtube') {
      playlist.hasMore = false;
      return [];
    }

    _PlaylistStreamSession? session = _sessions[listId];

    // If session doesn't exist or is exhausted, rebuild from stream and skip loaded count
    if (session == null || session.isExhausted) {
      debugPrint('[PlaylistPagination] Rebuilding stream session for $listId (skipping ${playlist.stems.length} items)...');
      final videoStream = _yt.playlists.getVideos(listId);
      final iterator = StreamIterator(videoStream);
      session = _PlaylistStreamSession(listId: listId, iterator: iterator);
      _sessions[listId] = session;

      int skipped = 0;
      final targetSkip = playlist.stems.length;
      try {
        while (skipped < targetSkip && await iterator.moveNext()) {
          skipped++;
        }
      } catch (e) {
        debugPrint('[PlaylistPagination] Error skipping items for $listId: $e');
      }
    }

    session.lastAccessed = DateTime.now();
    final existingIds = playlist.stems.map((s) => s.sourceId).toSet();
    final List<Stem> newStems = [];
    bool streamEnded = false;

    try {
      while (newStems.length < pageSize) {
        final hasNext = await session.iterator.moveNext();
        if (!hasNext) {
          streamEnded = true;
          break;
        }

        final video = session.iterator.current;
        if (existingIds.contains(video.id.value)) continue;
        existingIds.add(video.id.value);

        newStems.add(Stem(
          id: 'yt_${video.id.value}',
          title: video.title,
          artistName: video.author,
          artworkUrl: video.thumbnails.standardResUrl.isNotEmpty
              ? video.thumbnails.standardResUrl
              : (video.thumbnails.highResUrl.isNotEmpty
                  ? video.thumbnails.highResUrl
                  : playlist.artworkUrl),
          durationSec: video.duration?.inSeconds ?? 0,
          sourceId: video.id.value,
          albumName: playlist.name,
          playlistId: playlist.id,
          playlistTitle: playlist.name,
          playlistArtwork: playlist.artworkUrl,
        ));
      }

      if (streamEnded) {
        session.isExhausted = true;
        playlist.hasMore = false;
      }
    } catch (e) {
      debugPrint('[PlaylistPagination] Error fetching next page for $listId: $e');
      rethrow;
    }

    if (playlist.totalTrackCount != null &&
        (playlist.stems.length + newStems.length) >= playlist.totalTrackCount!) {
      playlist.hasMore = false;
    }

    playlist.stems.addAll(newStems);

    // Persist changes to Vault if saved
    try {
      await VaultService().updatePlaylist(playlist);
    } catch (e) {
      debugPrint('[PlaylistPagination] Failed to save updated playlist: $e');
    }

    debugPrint('[PlaylistPagination] Loaded ${newStems.length} new tracks for "${playlist.name}". Total now: ${playlist.stems.length} (hasMore: ${playlist.hasMore})');
    return newStems;
  }

  /// Cancels and cleans up any cached sessions to free resources.
  Future<void> disposeAll() async {
    for (final session in _sessions.values) {
      await session.dispose();
    }
    _sessions.clear();
  }
}
