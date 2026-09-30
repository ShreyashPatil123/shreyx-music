import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/playback_queue_controller.dart';

void main() {
  group('PlaybackQueueController Tests (Points 13, 14, 15, 16)', () {
    late PlaybackQueueController controller;

    setUp(() {
      controller = PlaybackQueueController();
    });

    tearDown(() {
      controller.dispose();
    });

    final testStems = [
      Stem(id: 's1', sourceId: 'src1', title: 'Track 1', artistName: 'Artist 1', artworkUrl: '', durationSec: 180),
      Stem(id: 's2', sourceId: 'src2', title: 'Track 2 (Fails)', artistName: 'Artist 2', artworkUrl: '', durationSec: 200),
      Stem(id: 's3', sourceId: 'src3', title: 'Track 3', artistName: 'Artist 3', artworkUrl: '', durationSec: 220),
    ];

    test('Initializes queue correctly', () {
      controller.setQueue(testStems);
      expect(controller.queue.length, equals(3));
      expect(controller.currentIndex, equals(0));
      expect(controller.currentTrack?.stem.title, equals('Track 1'));
    });

    test('Non-blocking failure recovery: failed track advances to next without breaking queue', () {
      controller.setQueue(testStems);

      // Play Track 1
      controller.updateActiveTrackState(TrackPlaybackState.playing);
      expect(controller.currentTrack?.state, equals(TrackPlaybackState.playing));

      // Advance to Track 2
      controller.advanceToNext();
      expect(controller.currentIndex, equals(1));
      expect(controller.currentTrack?.stem.title, equals('Track 2 (Fails)'));

      // Simulate Track 2 failure: must mark failed and auto-advance to Track 3
      final next = controller.handleCurrentTrackFailure('Network extraction failed');

      expect(next, isNotNull);
      expect(next!.stem.title, equals('Track 3'));
      expect(controller.currentIndex, equals(2));

      // Queue remains completely intact with 3 items
      expect(controller.queue.length, equals(3));
      expect(controller.queue[1].state, equals(TrackPlaybackState.failed));
      expect(controller.queue[1].errorMessage, equals('Network extraction failed'));
    });

    test('Queue end without LoopMode does not restart from 0 (Point 16)', () {
      controller.setQueue(testStems);
      controller.setLoopMode(LoopMode.off);

      controller.advanceToNext(); // to index 1
      controller.advanceToNext(); // to index 2 (last item)

      expect(controller.currentIndex, equals(2));

      // Attempting to advance past end returns null
      final beyond = controller.advanceToNext();
      expect(beyond, isNull);
      expect(controller.currentIndex, equals(2)); // Stays at 2, does NOT reset to 0!
    });

    test('Queue end with LoopMode.all wraps around to 0', () {
      controller.setQueue(testStems);
      controller.setLoopMode(LoopMode.all);

      controller.advanceToNext(); // index 1
      controller.advanceToNext(); // index 2

      final wrapped = controller.advanceToNext();
      expect(wrapped, isNotNull);
      expect(wrapped!.stem.title, equals('Track 1'));
      expect(controller.currentIndex, equals(0));
    });

    test('Shuffle and un-shuffle preserves all items without duplication or loss', () {
      controller.setQueue(testStems);
      expect(controller.isShuffled, isFalse);

      controller.setShuffled(true);
      expect(controller.isShuffled, isTrue);
      expect(controller.queue.length, equals(3));
      expect(controller.stems.map((s) => s.id).toSet(), equals(testStems.map((s) => s.id).toSet()));

      controller.setShuffled(false);
      expect(controller.isShuffled, isFalse);
      expect(controller.stems.map((s) => s.id).toList(), equals(testStems.map((s) => s.id).toList()));
    });
  });
}
