import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/stem.dart';
import 'track_preparation_service.dart';

class ResolvedStream {
  final String uri;
  final int durationSec;
  final DateTime expiresAt;
  final String resolvedVia;
  final Stem? effectiveStem;
  final String? userAgent;
  final String? fileExtension;

  String get url => uri;

  ResolvedStream({
    required this.uri,
    required this.durationSec,
    required this.expiresAt,
    required this.resolvedVia,
    this.effectiveStem,
    this.userAgent,
    this.fileExtension,
  });
}

/// Facade for stream resolution, delegating to the unified [TrackPreparationService].
class StreamResolver {
  static final StreamResolver _instance = StreamResolver._internal();
  factory StreamResolver() => _instance;
  StreamResolver._internal();

  final TrackPreparationService _preparation = TrackPreparationService();

  TrackPreparationService get preparation => _preparation;

  void clearCache() {
    _preparation.cache.clear();
  }

  void invalidateStream(String videoId) {
    _preparation.invalidateStream(videoId);
  }

  Future<bool> isStreamValid(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  Future<ResolvedStream> resolveStream(
    Stem stem, {
    String? diagnosticsSessionId,
  }) async {
    final prepared = await _preparation.prepareTrack(
      stem,
      diagnosticsSessionId: diagnosticsSessionId,
    );

    return ResolvedStream(
      uri: prepared.uri,
      durationSec: stem.durationSec > 0 ? stem.durationSec : 180,
      expiresAt: prepared.expiresAt,
      resolvedVia: prepared.resolver,
      effectiveStem: prepared.effectiveStem ?? stem,
      userAgent: prepared.userAgent,
      fileExtension: prepared.fileExtension,
    );
  }

  void dispose() {
    _preparation.dispose();
  }
}
