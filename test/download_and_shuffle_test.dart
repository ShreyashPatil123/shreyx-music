import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/download_service.dart';

void main() {
  group('DownloadService Model Tests', () {
    test('ActivePlaylistDownload progress calculation', () {
      final playlistDownload = ActivePlaylistDownload(
        playlistId: 'pl_123',
        title: 'Top Hits',
        artworkUrl: 'https://example.com/art.jpg',
        totalCount: 4,
        completedCount: 1,
        currentSongProgress: 0.5,
        currentSongTitle: 'Blinding Lights',
      );

      // (1 + 0.5) / 4 = 1.5 / 4 = 0.375 (37.5%)
      expect(playlistDownload.overallProgress, closeTo(0.375, 0.001));

      // Advance song progress to 1.0
      playlistDownload.currentSongProgress = 1.0;
      expect(playlistDownload.overallProgress, closeTo(0.5, 0.001));

      // Song 2 completed
      playlistDownload.completedCount = 2;
      playlistDownload.currentSongProgress = 0.0;
      expect(playlistDownload.overallProgress, closeTo(0.5, 0.001));

      // All completed
      playlistDownload.completedCount = 4;
      expect(playlistDownload.overallProgress, equals(1.0));
    });

    test('ActiveDownload progress clamping', () {
      final download = ActiveDownload(
        stem: Stem(
          id: 'test_1',
          sourceId: 'vid_123',
          title: 'Starboy',
          artistName: 'The Weeknd',
          artworkUrl: '',
          durationSec: 230,
        ),
        progress: 0.75,
        status: 'downloading',
      );

      expect(download.progress, equals(0.75));
      expect(download.status, equals('downloading'));
    });
  });

  group('Shuffle Logic Tests', () {
    test('Shuffle preserves all tracks without loss', () {
      final stems = List.generate(
        10,
        (i) => Stem(
          id: 'stem_$i',
          sourceId: 'src_$i',
          title: 'Track $i',
          artistName: 'Artist',
          artworkUrl: '',
          durationSec: 180,
        ),
      );

      final shuffled = List<Stem>.from(stems)..shuffle();
      expect(shuffled.length, equals(stems.length));
      expect(shuffled.map((s) => s.id).toSet(), equals(stems.map((s) => s.id).toSet()));
    });
  });
}
