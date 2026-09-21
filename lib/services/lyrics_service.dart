import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/lyric_line.dart';

class LyricsService {
  static String _cleanTitle(String title) {
    String cleaned = title;
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*Topic\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(Visualizer\)', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[Visualizer\]', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(Visualiser\)', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\|\s*Lyrics\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\([fF]eat\..*?\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\([fF]t\..*?\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[[fF]eat\..*?\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[[fF]t\..*?\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(Official.*?\)', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[Official.*?\]', caseSensitive: false), '');
    return cleaned.trim();
  }

  static String _cleanArtist(String artist) {
    String cleaned = artist;
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*Topic\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*Official\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*Music\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO\b', caseSensitive: false), '');
    return cleaned.trim();
  }

  static String _sanitizeForCache(String text) {
    return text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  static Future<File> _getCacheFile(String title, String artist) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/lyrics_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final safeTitle = _sanitizeForCache(title);
    final safeArtist = _sanitizeForCache(artist);
    return File('${cacheDir.path}/${safeTitle}_$safeArtist.json');
  }

  static Future<ParsedLyrics?> _readFromCache(String title, String artist) async {
    try {
      final file = await _getCacheFile(title, artist);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final linesData = data['lines'] as List<dynamic>? ?? [];
        final lines = linesData.map((e) {
          final map = e as Map<String, dynamic>;
          return LyricLine(timeMs: map['timeMs'] as int, text: map['text'] as String);
        }).toList();
        debugPrint('[Lyrics] Loaded from cache: ${file.path}');
        return ParsedLyrics(
          isSynced: data['isSynced'] as bool? ?? false,
          lines: lines,
          plainLyrics: data['plainLyrics'] as String?,
        );
      }
    } catch (e) {
      debugPrint('[Lyrics] Cache read error: $e');
    }
    return null;
  }

  static Future<void> _writeToCache(String title, String artist, ParsedLyrics lyrics) async {
    try {
      final file = await _getCacheFile(title, artist);
      final data = {
        'isSynced': lyrics.isSynced,
        'plainLyrics': lyrics.plainLyrics,
        'lines': lyrics.lines.map((e) => {'timeMs': e.timeMs, 'text': e.text}).toList(),
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint('[Lyrics] Saved to cache: ${file.path}');
    } catch (e) {
      debugPrint('[Lyrics] Cache write error: $e');
    }
  }

  static ParsedLyrics parseLrc(String lrcContent) {
    final lines = lrcContent.split('\n');
    final parsedLines = <LyricLine>[];
    String? plainLyrics;
    bool isSynced = false;

    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        isSynced = true;
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = int.parse(msStr.padRight(3, '0'));
        
        final timeMs = (min * 60 * 1000) + (sec * 1000) + ms;
        final text = line.substring(match.end).trim();
        
        parsedLines.add(LyricLine(timeMs: timeMs, text: text));
      } else {
        if (!isSynced && !line.startsWith('[')) {
          plainLyrics = (plainLyrics == null) ? line : '$plainLyrics\n$line';
        }
      }
    }

    parsedLines.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    if (parsedLines.isEmpty && plainLyrics == null) {
      plainLyrics = lrcContent;
    }

    return ParsedLyrics(
      isSynced: isSynced,
      lines: parsedLines,
      plainLyrics: plainLyrics,
    );
  }

  static int getActiveLineIndex(List<LyricLine> lines, num positionSec) {
    if (lines.isEmpty) return -1;
    final int positionMs = (positionSec * 1000).toInt();

    int left = 0;
    int right = lines.length - 1;
    int activeIndex = -1;

    while (left <= right) {
      int mid = left + (right - left) ~/ 2;
      if (lines[mid].timeMs <= positionMs) {
        activeIndex = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return activeIndex;
  }

  static Future<ParsedLyrics?> _fetchLRCLIB(String title, String artist, int? durationSec) async {
    try {
      debugPrint('[Lyrics] Fetching from LRCLIB for: $title - $artist');
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': title,
        'artist_name': artist,
        if (durationSec != null) 'duration': durationSec.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final syncedLrc = data['syncedLyrics'] as String?;
        final plainLrc = data['plainLyrics'] as String?;
        if (syncedLrc != null && syncedLrc.isNotEmpty) {
          return parseLrc(syncedLrc);
        } else if (plainLrc != null && plainLrc.isNotEmpty) {
          return ParsedLyrics(isSynced: false, lines: [], plainLyrics: plainLrc);
        }
      }
    } catch (e) {
      debugPrint('[Lyrics] LRCLIB error: $e');
    }
    return null;
  }

  static Future<ParsedLyrics?> _fetchKuGou(String title, String artist, int? durationSec) async {
    try {
      debugPrint('[Lyrics] Fetching from KuGou for: $title - $artist');
      // Step 1
      final keyword = '$title $artist'.trim();
      final uri1 = Uri.parse('https://mobilecdn.kugou.com/api/v3/search/song?keyword=${Uri.encodeComponent(keyword)}&page=1&pagesize=5');
      final res1 = await http.get(uri1).timeout(const Duration(seconds: 5));
      if (res1.statusCode != 200) return null;
      final data1 = jsonDecode(res1.body);
      final info = data1['data']?['info'] as List<dynamic>?;
      if (info == null || info.isEmpty) return null;
      
      String hash = '';
      int bestDiff = 999999;
      for (var item in info) {
        final h = item['hash'] as String?;
        final d = (item['duration'] as num?)?.toInt() ?? 0;
        if (h != null && h.isNotEmpty) {
          if (durationSec != null) {
            final diff = (d - durationSec).abs();
            if (diff < bestDiff) {
              bestDiff = diff;
              hash = h;
            }
          } else {
            hash = h;
            break;
          }
        }
      }
      if (hash.isEmpty) return null;

      // Step 2
      final durMs = durationSec != null ? durationSec * 1000 : 0;
      final uri2 = Uri.parse('https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=$durMs&hash=$hash');
      final res2 = await http.get(uri2).timeout(const Duration(seconds: 5));
      if (res2.statusCode != 200) return null;
      final data2 = jsonDecode(res2.body);
      final candidates = data2['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      
      final id = candidates[0]['id']?.toString();
      final accesskey = candidates[0]['accesskey']?.toString();
      if (id == null || accesskey == null) return null;

      // Step 3
      final uri3 = Uri.parse('https://krcs.kugou.com/download?ver=1&client=pc&id=$id&accesskey=$accesskey&fmt=lrc&charset=utf8');
      final res3 = await http.get(uri3).timeout(const Duration(seconds: 5));
      if (res3.statusCode != 200) return null;
      final data3 = jsonDecode(res3.body);
      final contentBase64 = data3['content'] as String?;
      if (contentBase64 == null || contentBase64.isEmpty) return null;

      final lrcBytes = base64Decode(contentBase64);
      final lrcText = utf8.decode(lrcBytes, allowMalformed: true);
      return parseLrc(lrcText);
    } catch (e) {
      debugPrint('[Lyrics] KuGou error: $e');
    }
    return null;
  }

  static Future<ParsedLyrics?> _fetchYoutube(String? sourceId) async {
    if (sourceId == null || sourceId.length != 11) return null;
    try {
      debugPrint('[Lyrics] Fetching from YouTube Captions for: $sourceId');
      final yt = YoutubeExplode();
      final manifest = await yt.videos.closedCaptions.getManifest(sourceId).timeout(const Duration(seconds: 5));
      final tracks = manifest.tracks;
      if (tracks.isEmpty) {
        yt.close();
        return null;
      }
      
      ClosedCaptionTrackInfo? selectedTrack;
      for (var track in tracks) {
        if (track.language.code.startsWith('en')) {
          selectedTrack = track;
          if (track.isAutoGenerated) {
            break;
          }
        }
      }
      if (selectedTrack == null) {
        yt.close();
        return null;
      }

      final trackData = await yt.videos.closedCaptions.get(selectedTrack).timeout(const Duration(seconds: 5));
      final lines = <LyricLine>[];
      for (var cc in trackData.captions) {
        lines.add(LyricLine(
          timeMs: cc.offset.inMilliseconds,
          text: cc.text,
        ));
      }
      yt.close();

      if (lines.isNotEmpty) {
        return ParsedLyrics(isSynced: true, lines: lines, plainLyrics: null);
      }
    } catch (e) {
      debugPrint('[Lyrics] YouTube Captions error: $e');
    }
    return null;
  }

  static Future<ParsedLyrics> fetchLyrics(String title, String artist, [int? durationSec, String? sourceId]) async {
    final cleanT = _cleanTitle(title);
    final cleanA = _cleanArtist(artist);
    
    // 1. Cache
    final cached = await _readFromCache(cleanT, cleanA);
    if (cached != null) return cached;

    // 2. LRCLIB
    ParsedLyrics? lyrics = await _fetchLRCLIB(cleanT, cleanA, durationSec);
    
    // 3. KuGou
    if (lyrics == null) {
      lyrics = await _fetchKuGou(cleanT, cleanA, durationSec);
    }
    
    // 4. YouTube Captions
    if (lyrics == null && sourceId != null) {
      lyrics = await _fetchYoutube(sourceId);
    }

    // 5. Finalize
    if (lyrics != null) {
      await _writeToCache(cleanT, cleanA, lyrics);
      return lyrics;
    }

    debugPrint('[Lyrics] No lyrics found across all sources.');
    return ParsedLyrics(isSynced: false, lines: [], plainLyrics: null);
  }
}
