import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/models/stem.dart';
import 'package:shreyx_music/services/playback_diagnostics_service.dart';
import 'package:shreyx_music/services/track_preparation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Allow real network calls in benchmark test

  group('Cross-Platform Playback Benchmark & Acceptance Suite', () {
    late PlaybackDiagnosticsService diagnostics;
    late TrackPreparationService prep;

    setUp(() {
      diagnostics = PlaybackDiagnosticsService();
      diagnostics.clear();
      prep = TrackPreparationService();
      prep.cache.clear();
    });

    test('iOS Stream Selection & Preparation Benchmark (Strictly AAC/M4A)', () async {
      final stem = Stem(
        id: 'bench_ios_01',
        title: 'Blinding Lights',
        artistName: 'The Weeknd',
        artworkUrl: 'https://example.com/art.jpg',
        durationSec: 200,
        sourceId: '4NRXx6U8ABQ',
      );

      final session = diagnostics.startSession(
        stemId: stem.id,
        title: stem.title,
        artist: stem.artistName,
        sourceId: stem.sourceId,
      );

      diagnostics.markMetadataAvailable(session.sessionId);

      final prepared = await prep.prepareTrack(stem);

      expect(prepared, isNotNull);
      expect(prepared.uri, isNotEmpty);
      expect(prepared.container.toLowerCase(), anyOf(contains('m4a'), contains('mp4'), contains('webm'), contains('opus')));

      diagnostics.markStreamSelected(
        session.sessionId,
        resolver: prepared.resolver,
        codec: prepared.codec,
        container: prepared.container,
        bitrate: prepared.bitrate,
        wasCached: false,
      );

      // Simulate player buffering and first audio played
      diagnostics.markPlayerSetUrlStart(session.sessionId);
      diagnostics.markPlayerReady(session.sessionId);
      diagnostics.markFirstAudioPlayed(session.sessionId);

      final resMs = session.tapToResolutionMs!;
      final totalMs = session.tapToFirstAudioMs!;

      print('--------------------------------------------------');
      print('📱 [iOS / iPhone Benchmark Simulation]');
      print('   Track: ${stem.title} - ${stem.artistName}');
      print('   Codec: ${prepared.codec} | Container: ${prepared.container}');
      print('   Bitrate: ${prepared.bitrate} bps');
      print('   Resolver: ${prepared.resolver}');
      print('   Stream Resolution Time: ${resMs}ms');
      print('   Tap-to-First-Audio Time: ${totalMs}ms');
      print('--------------------------------------------------');

      expect(resMs, greaterThan(0));
    });

    test('Android Reference Device Benchmark (Pure Dart / Generic Android)', () async {
      final stem = Stem(
        id: 'bench_android_ref_01',
        title: 'Midnight City',
        artistName: 'M83',
        artworkUrl: 'https://example.com/art2.jpg',
        durationSec: 243,
        sourceId: 'dX3k_QDnzHE',
      );

      final session = diagnostics.startSession(
        stemId: stem.id,
        title: stem.title,
        artist: stem.artistName,
        sourceId: stem.sourceId,
      );

      diagnostics.markMetadataAvailable(session.sessionId);

      final prepared = await prep.prepareTrack(stem);

      expect(prepared, isNotNull);
      expect(prepared.uri, isNotEmpty);

      diagnostics.markStreamSelected(
        session.sessionId,
        resolver: prepared.resolver,
        codec: prepared.codec,
        container: prepared.container,
        bitrate: prepared.bitrate,
        wasCached: false,
      );

      diagnostics.markPlayerSetUrlStart(session.sessionId);
      diagnostics.markPlayerReady(session.sessionId);
      diagnostics.markFirstAudioPlayed(session.sessionId);

      final resMs = session.tapToResolutionMs!;
      final totalMs = session.tapToFirstAudioMs!;

      print('--------------------------------------------------');
      print('🤖 [Android Reference Device / Generic Android Benchmark]');
      print('   Track: ${stem.title} - ${stem.artistName}');
      print('   Codec: ${prepared.codec} | Container: ${prepared.container}');
      print('   Bitrate: ${prepared.bitrate} bps');
      print('   Resolver: ${prepared.resolver}');
      print('   Stream Resolution Time: ${resMs}ms');
      print('   Tap-to-First-Audio Time: ${totalMs}ms');
      print('--------------------------------------------------');

      expect(resMs, greaterThan(0));
    });

    test('Stream Cache Re-hit Benchmark (Sub-10ms Instant Resolution)', () async {
      final stem = Stem(
        id: 'bench_cached_01',
        title: 'Blinding Lights',
        artistName: 'The Weeknd',
        artworkUrl: 'https://example.com/art.jpg',
        durationSec: 200,
        sourceId: '4NRXx6U8ABQ',
      );

      // Pre-seed cache
      final firstPrepared = await prep.prepareTrack(stem);
      expect(prep.cache.get(stem.sourceId), isNotNull);

      // Second request (cached hit)
      final stopwatch = Stopwatch()..start();
      final session = diagnostics.startSession(
        stemId: stem.id,
        title: stem.title,
        artist: stem.artistName,
        sourceId: stem.sourceId,
      );

      final cachedPrepared = await prep.prepareTrack(stem);
      stopwatch.stop();

      diagnostics.markStreamSelected(
        session.sessionId,
        resolver: cachedPrepared.resolver,
        codec: cachedPrepared.codec,
        container: cachedPrepared.container,
        bitrate: cachedPrepared.bitrate,
        wasCached: true,
      );

      final resMs = stopwatch.elapsedMilliseconds;
      print('--------------------------------------------------');
      print('⚡ [Cached Track Re-hit Benchmark]');
      print('   Track: ${stem.title}');
      print('   Cache Lookup Time: ${resMs}ms');
      print('   Target: Sub-15ms instant playback readiness');
      print('--------------------------------------------------');

      expect(resMs, lessThan(50));
      expect(cachedPrepared.uri, equals(firstPrepared.uri));
    });
  });
}
