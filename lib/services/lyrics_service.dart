import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsService {
  static final RegExp _lrcRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  static Future<ParsedLyrics> fetchLyrics(String title, String artist, [int? durationSec]) async {
    try {
      final cleanTitle = _cleanTitle(title);
      final cleanArtist = _cleanArtist(artist);

      final uri = Uri.parse('https://lrclib.net/api/get').replace(
        queryParameters: {
          'track_name': cleanTitle,
          'artist_name': cleanArtist,
          if (durationSec != null && durationSec > 0) 'duration': durationSec.toString(),
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final synced = data['syncedLyrics'] as String?;
        final plain = data['plainLyrics'] as String?;

        if (synced != null && synced.trim().isNotEmpty) {
          final lines = parseLrc(synced);
          return ParsedLyrics(isSynced: true, lines: lines, plainLyrics: plain);
        } else if (plain != null && plain.trim().isNotEmpty) {
          return ParsedLyrics(isSynced: false, lines: [], plainLyrics: plain);
        }
      }
    } catch (_) {}

    return ParsedLyrics(isSynced: false, lines: [], plainLyrics: null);
  }

  static List<LyricLine> parseLrc(String lrc) {
    final List<LyricLine> result = [];
    final rawLines = lrc.split('\n');

    for (final line in rawLines) {
      final match = _lrcRegex.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msRaw = match.group(3) ?? '0';
        final ms = (int.tryParse(msRaw) ?? 0) * (msRaw.length == 2 ? 10 : 1);
        final totalMs = min * 60000 + sec * 1000 + ms;
        final text = (match.group(4) ?? '').trim();
        if (text.isNotEmpty) {
          result.add(LyricLine(timeMs: totalMs, text: text));
        }
      }
    }

    result.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return result;
  }

  static int getActiveLineIndex(List<LyricLine> lines, double positionSec) {
    if (lines.isEmpty) return -1;
    final posMs = (positionSec * 1000).toInt();

    int low = 0;
    int high = lines.length - 1;
    int result = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].timeMs <= posMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }

  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*[\(\[](official\s*video|audio|lyrics|hd|4k|remix|feat\..*?)[\)\]]', caseSensitive: false), '')
        .trim();
  }

  static String _cleanArtist(String artist) {
    return artist
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
        .trim();
  }
}
