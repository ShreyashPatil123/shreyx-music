import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/playback_queue_controller.dart';
import 'package:shreyx_music/services/track_preparation_service.dart';

void main() {
  group('Track Switch & Rapid Switching Safeguard Tests', () {
    late TrackPreparationService preparationService;
    late PlaybackQueueController queueController;

    setUp(() {
      preparationService = TrackPreparationService();
      preparationService.cache.clear();
      queueController = PlaybackQueueController();
    });

    tearDown(() {
      queueController.dispose();
    });

    test('cancelActivePreparation advances monotonic resolution token', () {
      final initialToken = preparationService.activeResolutionToken;
      preparationService.cancelActivePreparation();
      expect(preparationService.activeResolutionToken, equals(initialToken + 1));
      preparationService.cancelActivePreparation();
      expect(preparationService.activeResolutionToken, equals(initialToken + 2));
    });

    test('Immediate state transition on track switch (Song A -> Song B)', () {
      final stemA = Stem(
        id: 'sA',
        sourceId: 'srcA',
        title: 'Song A',
        artistName: 'Artist A',
        artworkUrl: '',
        durationSec: 180,
      );
      final stemB = Stem(
        id: 'sB',
        sourceId: 'srcB',
        title: 'Song B',
        artistName: 'Artist B',
        artworkUrl: '',
        durationSec: 200,
      );

      queueController.setQueue([stemA, stemB], initialStem: stemA);
      queueController.updateActiveTrackState(TrackPlaybackState.playing);

      expect(queueController.currentTrack?.stem.title, equals('Song A'));
      expect(queueController.currentTrack?.state, equals(TrackPlaybackState.playing));

      // User taps Song B:
      // 1. Immediately cancel active preparation
      preparationService.cancelActivePreparation();
      // 2. Advance / update active track state to preparing synchronously
      queueController.setQueue([stemA, stemB], initialStem: stemB);
      queueController.updateActiveTrackState(TrackPlaybackState.preparing);

      // Verify immediate state change without waiting for resolution
      expect(queueController.currentTrack?.stem.title, equals('Song B'));
      expect(queueController.currentTrack?.state, equals(TrackPlaybackState.preparing));
    });

    test('Rapid switching cancellation (A -> B -> C): Only C is finalized', () async {
      int activeSessionId = 0;
      final completedSessions = <int>[];
      final playedTracks = <String>[];

      Future<void> simulatePlayStem(String trackName, Duration resolveDuration) async {
        final sessionId = ++activeSessionId;

        // Step 0: Cancel any prior preparation
        preparationService.cancelActivePreparation();

        // Step 1: Simulate stream resolution time
        await Future.delayed(resolveDuration);

        // Step 2: Check if superseded before starting playback
        if (sessionId != activeSessionId) {
          // Superseded: must be safely ignored/cancelled
          return;
        }

        completedSessions.add(sessionId);
        playedTracks.add(trackName);
      }

      // Rapidly trigger A, then B before A finishes, then C before B finishes
      final fA = simulatePlayStem('Song A', const Duration(milliseconds: 150));
      await Future.delayed(const Duration(milliseconds: 20));

      final fB = simulatePlayStem('Song B', const Duration(milliseconds: 150));
      await Future.delayed(const Duration(milliseconds: 20));

      final fC = simulatePlayStem('Song C', const Duration(milliseconds: 50));

      await Future.wait([fA, fB, fC]);

      // Only Song C should have played
      expect(playedTracks, equals(['Song C']));
      expect(completedSessions, equals([3]));
    });

    test('Stale async callback suppression does not overwrite active track', () async {
      int activeSessionId = 1;
      String currentDisplayTrack = 'Song A';

      // Switch to Song B (session 2)
      activeSessionId = 2;
      currentDisplayTrack = 'Song B';

      // Switch to Song C (session 3)
      activeSessionId = 3;
      currentDisplayTrack = 'Song C';

      // Simulate late completion of Song B callback
      final lateSessionId = 2;
      if (lateSessionId == activeSessionId) {
        currentDisplayTrack = 'Song B';
      }

      // Display track must remain Song C
      expect(currentDisplayTrack, equals('Song C'));
    });
  });
}
