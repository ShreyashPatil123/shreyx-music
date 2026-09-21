import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';

class InfiniteRadioService {
  static final InfiniteRadioService _instance = InfiniteRadioService._internal();

  factory InfiniteRadioService() => _instance;

  InfiniteRadioService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, List<Stem>> _cache = {};

  Future<List<Stem>> fetchRadioTracks(String videoId, {int count = 20}) async {
    String cleanId = videoId.trim();
    if (cleanId.startsWith('yt_')) {
      cleanId = cleanId.substring(3);
    }
    if (cleanId.contains('?v=')) {
      cleanId = cleanId.split('?v=').last.split('&').first;
    }
    if (cleanId.contains('/')) {
      cleanId = cleanId.split('/').last;
    }

    if (cleanId.isEmpty) {
      debugPrint('[InfiniteRadio] Empty videoId provided, skipping radio fetch');
      return [];
    }

    // Check fast in-memory cache (0ms instant return)
    if (_cache.containsKey(cleanId) && _cache[cleanId]!.isNotEmpty) {
      debugPrint('[InfiniteRadio] ⚡ In-memory cache hit for "$cleanId" (${_cache[cleanId]!.length} tracks)');
      return _cache[cleanId]!.take(count).toList();
    }

    final List<Stem> tracks = [];
    try {
      final innerTubeTracks = await _fetchFromInnerTube(cleanId, count: count);
      tracks.addAll(innerTubeTracks);
    } catch (e) {
      debugPrint('[InfiniteRadio] InnerTube request failed: $e');
    }

    if (tracks.isEmpty) {
      try {
        debugPrint('[InfiniteRadio] Falling back to youtube_explode_dart');
        final fallbackTracks = await _fetchFromYoutubeExplode(cleanId, count: count);
        tracks.addAll(fallbackTracks);
      } catch (e) {
        debugPrint('[InfiniteRadio] Youtube Explode fallback failed: $e');
      }
    }

    // Filter out the seed video and de-duplicate
    final result = tracks.where((stem) => stem.sourceId != cleanId && stem.sourceId != videoId).toList();
    
    final uniqueResult = <Stem>[];
    final seenIds = <String>{};
    for (final stem in result) {
      if (!seenIds.contains(stem.sourceId)) {
        seenIds.add(stem.sourceId);
        uniqueResult.add(stem);
      }
    }

    final finalTracks = uniqueResult.take(count).toList();
    if (finalTracks.isNotEmpty) {
      _cache[cleanId] = finalTracks;
      debugPrint('[InfiniteRadio] 📻 Cached ${finalTracks.length} radio tracks for "$cleanId"');
    }

    return finalTracks;
  }

  Future<List<Stem>> _fetchFromInnerTube(String videoId, {required int count}) async {
    final url = Uri.parse('https://music.youtube.com/youtubei/v1/next');
    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'playlistId': 'RDAMVM$videoId',
      'videoId': videoId,
    });

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      body: body,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final tracks = <Stem>[];

      try {
        final tabs = data['contents']['singleColumnMusicWatchNextResultsRenderer']['tabbedRenderer']['watchNextTabbedResultsRenderer']['tabs'] as List;
        final content = tabs[0]['tabRenderer']['content']['musicQueueRenderer']['content']['playlistPanelRenderer']['contents'] as List;

        for (final item in content) {
          if (item.containsKey('playlistPanelVideoRenderer')) {
            final renderer = item['playlistPanelVideoRenderer'];
            final id = renderer['videoId']?.toString() ?? '';
            if (id.isEmpty) continue;

            final title = renderer['title']?['runs']?[0]?['text']?.toString() ?? 'Unknown Title';
            final artist = renderer['longBylineText']?['runs']?[0]?['text']?.toString() ?? 'Unknown Artist';
            
            final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
            String artworkUrl = '';
            if (thumbnails != null && thumbnails.isNotEmpty) {
              artworkUrl = thumbnails.last['url']?.toString() ?? '';
            }

            final durationStr = renderer['lengthText']?['runs']?[0]?['text']?.toString() ?? '0:00';
            final durationSec = _parseDurationStr(durationStr);

            tracks.add(Stem(
              id: 'yt_$id',
              title: title,
              artistName: artist,
              artworkUrl: artworkUrl,
              durationSec: durationSec,
              sourceId: id,
            ));
          }
        }
        return tracks;
      } catch (e) {
        debugPrint('[InfiniteRadio] Error parsing InnerTube response: $e');
        return [];
      }
    } else {
      debugPrint('[InfiniteRadio] InnerTube returned status code ${response.statusCode}');
      return [];
    }
  }

  Future<List<Stem>> _fetchFromYoutubeExplode(String videoId, {required int count}) async {
    final tracks = <Stem>[];
    try {
      final video = await _yt.videos.get(videoId).timeout(const Duration(seconds: 3));
      final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 3));
      
      if (related != null && related.isNotEmpty) {
        for (final r in related) {
          tracks.add(Stem(
            id: 'yt_${r.id.value}',
            title: r.title,
            artistName: r.author,
            artworkUrl: r.thumbnails.highResUrl,
            durationSec: r.duration?.inSeconds ?? 0,
            sourceId: r.id.value,
          ));
        }
      } else {
        // Fallback search
        final searchResults = await _yt.search.search('${video.author} songs official audio').timeout(const Duration(seconds: 3));
        for (final r in searchResults) {
          tracks.add(Stem(
            id: 'yt_${r.id.value}',
            title: r.title,
            artistName: r.author,
            artworkUrl: r.thumbnails.highResUrl,
            durationSec: r.duration?.inSeconds ?? 0,
            sourceId: r.id.value,
          ));
        }
      }
    } catch (e) {
      debugPrint('[InfiniteRadio] Error in YoutubeExplode fallback: $e');
    }
    return tracks;
  }

  List<Stem> filterDuplicates(List<Stem> candidates, List<Stem> existingQueue) {
    final existingIds = existingQueue.map((s) => s.sourceId).toSet();
    return candidates.where((c) => !existingIds.contains(c.sourceId)).toList();
  }

  int _parseDurationStr(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = int.parse(parts[1]);
        return (m * 60) + s;
      } else if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final s = int.parse(parts[2]);
        return (h * 3600) + (m * 60) + s;
      }
    } catch (e) {
      debugPrint('[InfiniteRadio] Failed to parse duration "$durationStr": $e');
    }
    return 0;
  }
}
