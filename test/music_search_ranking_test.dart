import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/music_search_service.dart';
import 'package:shreyx_music/services/search_intent_analyzer.dart';

void main() {
  group('Music Search Intent & Ranking Tests (Safeguard 3)', () {
    final searchService = MusicSearchService();

    test('Demotes 70-80 minute mixes for normal song query (Perfect Ed Sheeran)', () {
      final query = 'Perfect Ed Sheeran';
      final intent = SearchIntentAnalyzer.analyze(query);
      expect(intent.isExplicitLongForm, isFalse);

      final candidates = [
        Stem(
          id: 'mix_1',
          sourceId: 'src_mix1',
          title: 'Best of Ed Sheeran 2024 - 1 Hour Romantic Hits Compilation',
          artistName: 'Top Hits Collection',
          artworkUrl: '',
          durationSec: 4680, // 78 minutes
        ),
        Stem(
          id: 'official_1',
          sourceId: 'src_perf',
          title: 'Ed Sheeran - Perfect (Official Music Video)',
          artistName: 'Ed Sheeran',
          artworkUrl: '',
          durationSec: 263, // 4m 23s
        ),
        Stem(
          id: 'audio_1',
          sourceId: 'src_audio',
          title: 'Ed Sheeran - Perfect (Official Audio)',
          artistName: 'Ed Sheeran',
          artworkUrl: '',
          durationSec: 263,
        ),
        Stem(
          id: 'live_1',
          sourceId: 'src_live',
          title: 'Ed Sheeran - Perfect (Live at Wembley Stadium)',
          artistName: 'Ed Sheeran',
          artworkUrl: '',
          durationSec: 290,
        ),
      ];

      final ranked = searchService.rankCandidates(candidates, intent);

      // Official audio/song must be ranked at the top (#1 and #2); 78-minute mix must be last
      expect(ranked.first.sourceId, equals('src_audio'));
      expect(ranked.last.sourceId, equals('src_mix1'));
    });

    test('Preserves long-form content when query explicitly requests a mix', () {
      final query = 'Bollywood workout mix';
      final intent = SearchIntentAnalyzer.analyze(query);
      expect(intent.isExplicitLongForm, isTrue);

      final candidates = [
        Stem(
          id: 'short_1',
          sourceId: 'src_short',
          title: 'Short Bollywood Song Preview',
          artistName: 'Bollywood Music',
          artworkUrl: '',
          durationSec: 90,
        ),
        Stem(
          id: 'mix_1',
          sourceId: 'src_gym_mix',
          title: 'Nonstop Bollywood Workout Mix 2024 - High Energy Gym Compilation',
          artistName: 'DJ Fitness Records',
          artworkUrl: '',
          durationSec: 3600, // 60 minutes
        ),
      ];

      final ranked = searchService.rankCandidates(candidates, intent);

      // Mix must be prioritized because user explicitly requested a workout mix
      expect(ranked.first.sourceId, equals('src_gym_mix'));
    });

    test('Does not penalize legitimate long songs (6-9 minutes)', () {
      final query = 'Bohemian Rhapsody Queen';
      final intent = SearchIntentAnalyzer.analyze(query);

      final candidates = [
        Stem(
          id: 'song_1',
          sourceId: 'src_queen',
          title: 'Queen – Bohemian Rhapsody (Official Video Remastered)',
          artistName: 'Queen Official',
          artworkUrl: '',
          durationSec: 360, // 6 minutes (legitimate longer song)
        ),
        Stem(
          id: 'mix_1',
          sourceId: 'src_queen_mix',
          title: 'Queen Greatest Hits 1970-1990 Full Album Nonstop Mix',
          artistName: 'Rock Classics Hub',
          artworkUrl: '',
          durationSec: 5400, // 90 minutes
        ),
      ];

      final ranked = searchService.rankCandidates(candidates, intent);
      expect(ranked.first.sourceId, equals('src_queen'));
    });

    test('Promotes requested artistic variants (e.g. acoustic)', () {
      final query = 'Blinding Lights acoustic';
      final intent = SearchIntentAnalyzer.analyze(query);
      expect(intent.requestedVariants, contains('acoustic'));

      final candidates = [
        Stem(
          id: 'std_1',
          sourceId: 'src_std',
          title: 'The Weeknd - Blinding Lights (Official Audio)',
          artistName: 'The Weeknd',
          artworkUrl: '',
          durationSec: 200,
        ),
        Stem(
          id: 'ac_1',
          sourceId: 'src_acoustic',
          title: 'The Weeknd - Blinding Lights (Acoustic Version)',
          artistName: 'The Weeknd',
          artworkUrl: '',
          durationSec: 215,
        ),
      ];

      final ranked = searchService.rankCandidates(candidates, intent);
      expect(ranked.first.sourceId, equals('src_acoustic'));
    });
  });
}
