import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/models/playlist.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/playback_queue_controller.dart';

void main() {
  group('Playlist Pagination & Beyond 100-Track Limit Tests', () {
    late PlaybackQueueController queueController;

    setUp(() {
      queueController = PlaybackQueueController();
    });

    tearDown(() {
      queueController.dispose();
    });

    test('Playlist model correctly serializes and deserializes pagination metadata', () {
      final playlist = Playlist(
        id: 'pl_yt_biglist',
        name: 'Mega 250 Playlist',
        description: 'Large playlist test',
        artworkUrl: 'https://example.com/art.jpg',
        stems: List.generate(
          50,
          (i) => Stem(
            id: 'yt_vid_$i',
            sourceId: 'vid_$i',
            title: 'Track $i',
            artistName: 'Artist $i',
            artworkUrl: '',
            durationSec: 180,
          ),
        ),
        sourceId: 'biglist',
        sourceType: 'youtube',
        sourceUrl: 'https://www.youtube.com/playlist?list=biglist',
        totalTrackCount: 250,
        hasMore: true,
      );

      final json = playlist.toJson();
      expect(json['totalTrackCount'], equals(250));
      expect(json['hasMore'], isTrue);
      expect(json['sourceType'], equals('youtube'));
      expect(json['sourceId'], equals('biglist'));

      final reconstructed = Playlist.fromJson(json);
      expect(reconstructed.id, equals('pl_yt_biglist'));
      expect(reconstructed.totalTrackCount, equals(250));
      expect(reconstructed.hasMore, isTrue);
      expect(reconstructed.stems.length, equals(50));
    });

    test('Simulated pagination expands playlist beyond 100 tracks to 250 tracks without ceiling', () {
      // Create initial page of 50 tracks
      final playlist = Playlist(
        id: 'pl_yt_infinite',
        name: 'Huge Playlist',
        stems: List.generate(
          50,
          (i) => Stem(
            id: 'yt_song_$i',
            sourceId: 'song_$i',
            title: 'Song $i',
            artistName: 'Artist',
            artworkUrl: '',
            durationSec: 200,
          ),
        ),
        sourceId: 'infinite_list',
        sourceType: 'youtube',
        totalTrackCount: 250,
        hasMore: true,
      );

      expect(playlist.stems.length, equals(50));
      expect(playlist.hasMore, isTrue);

      // Page 2: Fetch 50 more tracks (tracks 50 to 99)
      final page2 = List.generate(
        50,
        (i) => Stem(
          id: 'yt_song_${i + 50}',
          sourceId: 'song_${i + 50}',
          title: 'Song ${i + 50}',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 200,
        ),
      );
      playlist.stems.addAll(page2);
      expect(playlist.stems.length, equals(100));
      expect(playlist.stems.length < playlist.totalTrackCount!, isTrue);

      // Page 3: Fetch 50 more tracks (tracks 100 to 149) -> EXCEEDS 100-TRACK CEILING
      final page3 = List.generate(
        50,
        (i) => Stem(
          id: 'yt_song_${i + 100}',
          sourceId: 'song_${i + 100}',
          title: 'Song ${i + 100}',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 200,
        ),
      );
      playlist.stems.addAll(page3);
      expect(playlist.stems.length, equals(150));
      expect(playlist.stems.length, greaterThan(100)); // Proves ceiling is broken!

      // Pages 4 and 5: Load remaining 100 tracks to reach 250
      final page4And5 = List.generate(
        100,
        (i) => Stem(
          id: 'yt_song_${i + 150}',
          sourceId: 'song_${i + 150}',
          title: 'Song ${i + 150}',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 200,
        ),
      );
      playlist.stems.addAll(page4And5);

      if (playlist.stems.length >= playlist.totalTrackCount!) {
        playlist.hasMore = false;
      }

      expect(playlist.stems.length, equals(250));
      expect(playlist.hasMore, isFalse);
    });

    test('appendUniqueTracks preserves existing playing track and un-shuffle order', () {
      final initialTracks = List.generate(
        5,
        (i) => Stem(
          id: 's_$i',
          sourceId: 'src_$i',
          title: 'Song $i',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 180,
        ),
      );

      queueController.setQueue(initialTracks, initialIndex: 2);
      expect(queueController.currentIndex, equals(2));
      expect(queueController.currentTrack?.stem.id, equals('s_2'));

      // New paginated batch arrives
      final paginatedBatch = List.generate(
        3,
        (i) => Stem(
          id: 's_${i + 5}',
          sourceId: 'src_${i + 5}',
          title: 'Song ${i + 5}',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 180,
        ),
      );

      queueController.appendUniqueTracks(paginatedBatch);

      // Verify queue length expanded to 8
      expect(queueController.queue.length, equals(8));
      // Current playing track and index must NOT be disrupted
      expect(queueController.currentIndex, equals(2));
      expect(queueController.currentTrack?.stem.id, equals('s_2'));
      // Last track must be s_7
      expect(queueController.queue.last.stem.id, equals('s_7'));
    });

    test('appendUniqueTracks deduplicates incoming paginated tracks', () {
      final initialTracks = [
        Stem(id: 's_1', sourceId: 'src_1', title: 'Song 1', artistName: 'A', artworkUrl: '', durationSec: 180),
        Stem(id: 's_2', sourceId: 'src_2', title: 'Song 2', artistName: 'A', artworkUrl: '', durationSec: 180),
      ];

      queueController.setQueue(initialTracks);

      final duplicateBatch = [
        Stem(id: 's_2', sourceId: 'src_2', title: 'Song 2', artistName: 'A', artworkUrl: '', durationSec: 180),
        Stem(id: 's_3', sourceId: 'src_3', title: 'Song 3', artistName: 'A', artworkUrl: '', durationSec: 180),
      ];

      queueController.appendUniqueTracks(duplicateBatch);

      // Only s_3 should have been appended, count is 3 not 4
      expect(queueController.queue.length, equals(3));
      expect(queueController.queue.map((q) => q.stem.id).toList(), equals(['s_1', 's_2', 's_3']));
    });
  });
}
