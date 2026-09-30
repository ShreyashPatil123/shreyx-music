import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/services/prepared_track_cache.dart';

void main() {
  group('PreparedTrackCache Tests (Safeguard 2)', () {
    final cache = PreparedTrackCache();

    setUp(() {
      cache.clear();
    });

    test('Stores and retrieves unexpired prepared track', () {
      final track = PreparedTrack(
        videoId: 'vid_123',
        uri: 'https://rr1---sn.googlevideo.com/videoplayback?id=vid_123',
        codec: 'audio/webm',
        container: 'webm',
        bitrate: 160000,
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        resolvedAt: DateTime.now(),
        resolver: 'native_newpipe',
        fileExtension: 'webm',
      );

      cache.put(track);
      final retrieved = cache.get('vid_123');

      expect(retrieved, isNotNull);
      expect(retrieved!.videoId, equals('vid_123'));
      expect(retrieved.uri, equals(track.uri));
      expect(retrieved.fileExtension, equals('webm'));
    });

    test('Purges expired track on get and returns null', () {
      final expiredTrack = PreparedTrack(
        videoId: 'vid_expired',
        uri: 'https://rr1---sn.googlevideo.com/videoplayback?id=vid_expired',
        codec: 'audio/webm',
        container: 'webm',
        bitrate: 160000,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        resolvedAt: DateTime.now().subtract(const Duration(hours: 4)),
        resolver: 'native_newpipe',
        fileExtension: 'webm',
      );

      cache.put(expiredTrack);
      final retrieved = cache.get('vid_expired');

      expect(retrieved, isNull);
      expect(cache.size, equals(0));
    });

    test('Deterministically invalidates track upon error (Safeguard 2)', () {
      final track = PreparedTrack(
        videoId: 'vid_403',
        uri: 'https://rr1---sn.googlevideo.com/videoplayback?id=vid_403',
        codec: 'audio/mp4',
        container: 'm4a',
        bitrate: 128000,
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        resolvedAt: DateTime.now(),
        resolver: 'youtube_explode_dart',
        fileExtension: 'm4a',
      );

      cache.put(track);
      expect(cache.get('vid_403'), isNotNull);

      // Player reported 403 / unplayable -> immediate invalidation
      cache.invalidate('vid_403');
      expect(cache.get('vid_403'), isNull);
    });

    test('Clamps expiry to safety ceiling (max 3 hours)', () {
      final distantTrack = PreparedTrack(
        videoId: 'vid_distant',
        uri: 'https://rr1---sn.googlevideo.com/videoplayback?id=vid_distant',
        codec: 'audio/webm',
        container: 'webm',
        bitrate: 160000,
        expiresAt: DateTime.now().add(const Duration(days: 30)), // Claimed 30 days
        resolvedAt: DateTime.now(),
        resolver: 'native_newpipe',
        fileExtension: 'webm',
      );

      cache.put(distantTrack);
      final retrieved = cache.get('vid_distant');

      expect(retrieved, isNotNull);
      // Expiry must be clamped to <= 3 hours from now
      final maxExpected = DateTime.now().add(const Duration(hours: 3, minutes: 1));
      expect(retrieved!.expiresAt.isBefore(maxExpected), isTrue);
    });
  });
}
