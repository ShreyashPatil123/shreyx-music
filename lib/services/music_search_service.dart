import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';
import '../utils/music_title_normalizer.dart';
import 'search_intent_analyzer.dart';
import 'vault_service.dart';

class ScoredCandidate {
  final Stem stem;
  final double score;
  final String canonicalTitle;

  ScoredCandidate({
    required this.stem,
    required this.score,
    required this.canonicalTitle,
  });
}

/// Music-focused search and ranking service.
///
/// Implements Safeguard 3: Exact title & artist matches are primary signals,
/// official music channels are weighted, duration is an auxiliary signal
/// that demotes 70-80 min mixes for song queries without penalizing legitimate long songs,
/// and explicit long-form intent is fully respected.
class MusicSearchService {
  static final MusicSearchService _instance = MusicSearchService._internal();
  factory MusicSearchService() => _instance;
  MusicSearchService._internal();

  final YoutubeExplode _yt = YoutubeExplode();

  /// Searches and ranks music candidates according to intent, title/artist match,
  /// duration, channel authenticity, and accountless local affinity.
  Future<List<Stem>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final intent = SearchIntentAnalyzer.analyze(cleanQuery);
    final rawCandidates = await _fetchCandidates(cleanQuery);
    if (rawCandidates.isEmpty) return [];

    return rankCandidates(rawCandidates, intent);
  }

  /// Fetches candidates from YouTube with error handling.
  Future<List<Stem>> _fetchCandidates(String query) async {
    final List<Stem> results = [];
    try {
      final searchList = await _yt.search.search(query).timeout(const Duration(seconds: 7));
      for (final video in searchList.take(30)) {
        final dur = video.duration?.inSeconds ?? 0;
        final thumb = video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.standardResUrl;

        results.add(Stem(
          id: 'yt_${video.id.value}',
          title: video.title,
          artistName: video.author,
          artworkUrl: thumb,
          durationSec: dur,
          sourceId: video.id.value,
        ));
      }
    } catch (e) {
      debugPrint('[MusicSearchService] Search fetch error: $e');
    }
    return results;
  }

  /// Deterministically scores and ranks candidates based on query intent and music features.
  List<Stem> rankCandidates(List<Stem> candidates, SearchIntent intent) {
    if (candidates.isEmpty) return [];

    final normQuery = intent.normalizedQuery;
    final queryTokens = normQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final vault = VaultService();

    final List<ScoredCandidate> scoredList = [];

    for (final stem in candidates) {
      double score = 0.0;
      final rawTitle = stem.title;
      final normTitle = MusicTitleNormalizer.normalize(rawTitle).toLowerCase();
      final normArtist = stem.artistName.toLowerCase();
      final durSec = stem.durationSec;

      // 1. EXACT & NEAR-EXACT TITLE MATCH (PRIMARY SIGNAL: up to +100)
      if (normTitle == normQuery) {
        score += 100.0;
      } else if (normTitle.startsWith(normQuery) || normQuery.startsWith(normTitle)) {
        score += 75.0;
      } else if (normTitle.contains(normQuery)) {
        score += 60.0;
      } else {
        // Token match ratio
        int matchedTokens = 0;
        for (final token in queryTokens) {
          if (normTitle.contains(token)) matchedTokens++;
        }
        if (queryTokens.isNotEmpty) {
          score += (matchedTokens / queryTokens.length) * 45.0;
        }
      }

      // 2. ARTIST MATCHING (PRIMARY SIGNAL: up to +50)
      for (final token in queryTokens) {
        if (normArtist.contains(token) && token.length > 2) {
          score += 25.0;
          break;
        }
      }
      if (normQuery.contains(normArtist) && normArtist.isNotEmpty) {
        score += 35.0;
      }

      // 3. OFFICIAL MUSIC EVIDENCE (up to +40)
      final lowerAuthor = normArtist;
      if (lowerAuthor.contains('vevo') ||
          lowerAuthor.contains('official') ||
          lowerAuthor.contains('records') ||
          lowerAuthor.contains('topic') ||
          lowerAuthor.contains('music')) {
        score += 30.0;
      }
      if (rawTitle.toLowerCase().contains('official audio') ||
          rawTitle.toLowerCase().contains('official music video')) {
        score += 15.0;
      }

      // 4. AUXILIARY DURATION SIGNAL (Safeguard 3: soft signal, not rigid filter)
      if (intent.isExplicitLongForm) {
        // User explicitly asked for a mix, playlist, 1 hour, or compilation:
        // DO NOT penalize long-form! Instead, favor longer content
        if (durSec >= 1200) {
          score += 40.0; // 20+ min mix favored
        } else if (durSec >= 600) {
          score += 20.0;
        }
      } else {
        // User searched for a song:
        // Demote 70-80 minute mixes without penalizing genuine songs
        if (durSec >= 120 && durSec <= 360) {
          // 2 to 6 minutes: ideal song length
          score += 40.0;
        } else if (durSec > 360 && durSec <= 600) {
          // 6 to 10 minutes: legitimate longer song (prog rock, extended mix, etc.)
          score += 20.0;
        } else if (durSec > 600 && durSec <= 1080) {
          // 10 to 18 minutes: slight demotion
          score -= 20.0;
        } else if (durSec > 1080 && durSec <= 2700) {
          // 18 to 45 minutes: strong demotion
          score -= 75.0;
        } else if (durSec > 2700) {
          // 45+ minutes (70-80 minute mixes): heavy demotion
          score -= 150.0;
        }
      }

      // 5. ARTISTIC VARIANT ALIGNMENT
      final candidateVariants = MusicTitleNormalizer.extractDescriptors(rawTitle);
      if (intent.requestedVariants.isNotEmpty) {
        for (final req in intent.requestedVariants) {
          if (candidateVariants.contains(req) || normTitle.contains(req)) {
            score += 40.0;
          }
        }
      } else {
        // If user didn't request a variant, favor canonical studio master over remix/live
        if (candidateVariants.isEmpty) {
          score += 15.0;
        }
      }

      // 6. LOCAL ACCOUNTLESS AFFINITY (Privacy-first personalization: +25)
      if (vault.isFavorite(stem.id) || vault.isFavorite(stem.sourceId)) {
        score += 25.0;
      }

      scoredList.add(ScoredCandidate(
        stem: stem,
        score: score,
        canonicalTitle: normTitle,
      ));
    }

    // Deterministic Sort: Higher score first, tie-break by sourceId
    scoredList.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.stem.sourceId.compareTo(b.stem.sourceId);
    });

    // 7. CANONICAL GROUPING / DEDUPLICATION
    // Filter out near-identical duplicate video IDs
    final seenSources = <String>{};
    final List<Stem> rankedStems = [];

    for (final sc in scoredList) {
      if (!seenSources.contains(sc.stem.sourceId)) {
        seenSources.add(sc.stem.sourceId);
        rankedStems.add(sc.stem);
      }
    }

    return rankedStems;
  }

  void dispose() {
    _yt.close();
  }
}
