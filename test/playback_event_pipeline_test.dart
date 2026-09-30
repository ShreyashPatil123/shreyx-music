import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/playback_event_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackEventPipeline Tests (Points 26, 27, 28)', () {
    late PlaybackEventPipeline pipeline;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      pipeline = PlaybackEventPipeline();
      await pipeline.init();
      await pipeline.clearHistory();
    });

    final stem1 = Stem(
      id: 'stem_1',
      sourceId: 'src_1',
      title: 'Blinding Lights',
      artistName: 'The Weeknd',
      artworkUrl: 'https://example.com/art1.jpg',
      durationSec: 200,
    );

    final stem2 = Stem(
      id: 'stem_2',
      sourceId: 'src_2',
      title: 'Starboy',
      artistName: 'The Weeknd',
      artworkUrl: 'https://example.com/art2.jpg',
      durationSec: 230,
    );

    test('Prevents duplicate history entries for same playback session (Point 27)', () async {
      const sessionId = 'session_xyz_1';

      // Simulate play requested
      pipeline.onPlayRequested(stem1, sessionId: sessionId);

      // Play started
      await pipeline.onPlayStarted(stem1, sessionId: sessionId);
      expect(pipeline.getRecentlyPlayed().length, equals(1));
      expect(pipeline.getPlayCount(stem1.id), equals(1));

      // Simulate player retry or crossfade re-triggering with SAME sessionId
      await pipeline.onPlayStarted(stem1, sessionId: sessionId);

      // Must NOT create a second duplicate history entry or increment count again
      expect(pipeline.getRecentlyPlayed().length, equals(1));
      expect(pipeline.getPlayCount(stem1.id), equals(1));
    });

    test('Tracks Continue Listening category for tracks paused midway (10% to 90%)', () async {
      const sessionId = 'session_midway';
      await pipeline.onPlayStarted(stem1, sessionId: sessionId);

      // 50% through track (100s / 200s)
      pipeline.onPlayProgress(
        sessionId: sessionId,
        position: const Duration(seconds: 100),
        total: const Duration(seconds: 200),
      );

      final continueList = pipeline.getContinueListening();
      expect(continueList.length, equals(1));
      expect(continueList.first.id, equals('stem_1'));

      // If track completes 100%, it should no longer be in Continue Listening
      await pipeline.onPlayCompleted(sessionId: sessionId);
      final afterComplete = pipeline.getContinueListening();
      expect(afterComplete.isEmpty, isTrue);
    });

    test('Tracks Most Played based on lifetime play counts', () async {
      // Play stem1 twice with different sessions
      await pipeline.onPlayStarted(stem1, sessionId: 's1');
      await pipeline.onPlayStarted(stem1, sessionId: 's2');

      // Play stem2 three times
      await pipeline.onPlayStarted(stem2, sessionId: 's3');
      await pipeline.onPlayStarted(stem2, sessionId: 's4');
      await pipeline.onPlayStarted(stem2, sessionId: 's5');

      final mostPlayed = pipeline.getMostPlayed();
      expect(mostPlayed.length, equals(2));
      expect(mostPlayed.first.id, equals('stem_2')); // 3 plays
      expect(mostPlayed.last.id, equals('stem_1'));  // 2 plays
    });
  });
}
