import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/stem.dart';

class MoodCategory {
  final String title;
  final String? browseParams;

  MoodCategory({required this.title, this.browseParams});
}

class InnertubeFeedService {
  static final InnertubeFeedService _instance = InnertubeFeedService._internal();

  factory InnertubeFeedService() {
    return _instance;
  }

  InnertubeFeedService._internal();

  Future<Map<String, dynamic>> _browse(String browseId, {Map<String, String>? params}) async {
    try {
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/browse?prettyPrint=false');
      final body = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US'
          }
        },
        'browseId': browseId,
      };

      if (params != null) {
        body.addAll(params);
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('[InnertubeFeed] Browse request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[InnertubeFeed] Browse error: $e');
    }
    return {};
  }

  Future<List<Stem>> fetchCharts() async {
    try {
      final data = await _browse('FEmusic_charts');
      if (data.isEmpty) return [];

      final items = _extractMusicItems(data);
      List<Stem> stems = [];
      for (var item in items) {
        final stem = _parseToStem(item);
        if (stem != null && !stems.any((s) => s.id == stem.id)) {
          stems.add(stem);
          if (stems.length >= 30) break;
        }
      }
      return stems;
    } catch (e) {
      debugPrint('[InnertubeFeed] Error fetching charts: $e');
      return [];
    }
  }

  Future<List<MoodCategory>> fetchMoodsAndGenres() async {
    try {
      final data = await _browse('FEmusic_moods_and_genres');
      if (data.isEmpty) return [];

      List<MoodCategory> categories = [];
      
      void extractCategories(dynamic obj) {
        if (obj is Map<String, dynamic>) {
          if (obj.containsKey('musicNavigationButtonRenderer')) {
            final renderer = obj['musicNavigationButtonRenderer'];
            final text = renderer['buttonText']?['runs']?[0]?['text'] as String?;
            final endpoint = renderer['clickCommand'] ?? renderer['navigationEndpoint'];
            final browseId = endpoint?['browseEndpoint']?['browseId'] as String?;
            final params = endpoint?['browseEndpoint']?['params'] as String?;
            
            if (text != null && text.isNotEmpty) {
              // We might pass params directly or combine them
              categories.add(MoodCategory(title: text, browseParams: params ?? browseId));
            }
          }
          obj.values.forEach(extractCategories);
        } else if (obj is List) {
          obj.forEach(extractCategories);
        }
      }
      
      extractCategories(data);
      return categories;
    } catch (e) {
      debugPrint('[InnertubeFeed] Error fetching moods and genres: $e');
      return [];
    }
  }

  Future<List<Stem>> fetchMoodPlaylist(String moodParams) async {
    try {
      // Mood params might be a browseId or actual params for a specific browse endpoint
      // Usually, clicking a mood gives a new browseId. We will just use it as browseId.
      final data = await _browse(moodParams);
      if (data.isEmpty) return [];

      final items = _extractMusicItems(data);
      List<Stem> stems = [];
      for (var item in items) {
        final stem = _parseToStem(item);
        if (stem != null && !stems.any((s) => s.id == stem.id)) {
          stems.add(stem);
        }
      }
      return stems;
    } catch (e) {
      debugPrint('[InnertubeFeed] Error fetching mood playlist: $e');
      return [];
    }
  }

  Future<List<Stem>> fetchNewReleases() async {
    try {
      final data = await _browse('FEmusic_new_releases_albums');
      if (data.isEmpty) return [];

      final items = _extractMusicItems(data);
      List<Stem> stems = [];
      for (var item in items) {
        final stem = _parseToStem(item);
        if (stem != null && !stems.any((s) => s.id == stem.id)) {
          stems.add(stem);
          if (stems.length >= 30) break;
        }
      }
      return stems;
    } catch (e) {
      debugPrint('[InnertubeFeed] Error fetching new releases: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _extractMusicItems(Map<String, dynamic> json) {
    List<Map<String, dynamic>> results = [];

    void recurse(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        if (obj.containsKey('musicResponsiveListItemRenderer')) {
          results.add(obj['musicResponsiveListItemRenderer']);
        } else if (obj.containsKey('musicTwoRowItemRenderer')) {
          results.add(obj['musicTwoRowItemRenderer']);
        } else if (obj.containsKey('playlistPanelVideoRenderer')) {
          results.add(obj['playlistPanelVideoRenderer']);
        }
        obj.values.forEach(recurse);
      } else if (obj is List) {
        obj.forEach(recurse);
      }
    }

    recurse(json);
    return results;
  }

  Stem? _parseToStem(Map<String, dynamic> renderer) {
    try {
      String? videoId;
      String title = 'Unknown Title';
      String artist = 'Unknown Artist';
      String? thumbnail;
      int duration = 0;

      // Extract videoId
      if (renderer.containsKey('videoId')) {
        videoId = renderer['videoId'];
      } else if (renderer['playlistItemData']?['videoId'] != null) {
        videoId = renderer['playlistItemData']['videoId'];
      } else if (renderer['navigationEndpoint']?['watchEndpoint']?['videoId'] != null) {
        videoId = renderer['navigationEndpoint']['watchEndpoint']['videoId'];
      }
      
      // Try finding videoId inside flexColumns or similar if not found yet
      if (videoId == null) {
        // Deep search for watchEndpoint
        String? foundVideoId;
        void findVideoId(dynamic obj) {
          if (foundVideoId != null) return;
          if (obj is Map<String, dynamic>) {
            if (obj['watchEndpoint']?['videoId'] != null) {
              foundVideoId = obj['watchEndpoint']['videoId'];
              return;
            }
            obj.values.forEach(findVideoId);
          } else if (obj is List) {
            obj.forEach(findVideoId);
          }
        }
        findVideoId(renderer);
        videoId = foundVideoId;
      }

      if (videoId == null || videoId.isEmpty) return null;

      // Extract title
      final titleRuns = renderer['title']?['runs'] ??
          renderer['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      if (titleRuns != null && titleRuns.isNotEmpty) {
        title = titleRuns[0]['text'] ?? title;
      }

      // Extract artist/subtitle
      final subtitleRuns = renderer['subtitle']?['runs'] ??
          renderer['shortBylineText']?['runs'] ??
          renderer['flexColumns']?[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
      if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
        // Combine all text pieces that aren't separators like " • "
        artist = (subtitleRuns as List)
            .map((r) => r['text'] as String)
            .where((t) => t != ' • ')
            .join(' ');
      }

      // Extract thumbnail
      final thumbnailsList = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
          renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
          renderer['thumbnail']?['thumbnails'];
      if (thumbnailsList != null && thumbnailsList.isNotEmpty) {
        // Get highest res thumbnail
        thumbnail = (thumbnailsList as List).last['url'];
      }

      // Extract duration
      String? durationStr;
      if (renderer.containsKey('lengthText')) {
        durationStr = renderer['lengthText']?['runs']?[0]?['text'];
      } else {
        // Check fixed columns for duration
        final fixedColumns = renderer['fixedColumns'];
        if (fixedColumns != null) {
          for (var col in fixedColumns) {
            final colText = col['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text'];
            if (colText != null && RegExp(r'^\d+:\d+').hasMatch(colText)) {
              durationStr = colText;
              break;
            }
          }
        }
      }

      if (durationStr != null) {
        duration = _parseDuration(durationStr);
      }

      return Stem(
        id: 'yt_$videoId',
        title: title,
        artistName: artist,
        artworkUrl: thumbnail ?? '',
        durationSec: duration,
        sourceId: videoId,
      );
    } catch (e) {
      debugPrint('[InnertubeFeed] Error parsing item to stem: $e');
      return null;
    }
  }

  int _parseDuration(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else if (parts.length == 3) {
        return int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2]);
      }
    } catch (e) {
      debugPrint('[InnertubeFeed] Error parsing duration: $e');
    }
    return 0;
  }
}
