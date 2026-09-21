import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';

class ResolvedStream {
  final String uri;
  final int durationSec;
  final DateTime expiresAt;
  final String resolvedVia;
  final Stem? effectiveStem;
  final String? userAgent;

  String get url => uri;

  ResolvedStream({
    required this.uri,
    required this.durationSec,
    required this.expiresAt,
    required this.resolvedVia,
    this.effectiveStem,
    this.userAgent,
  });
}

class StreamResolver {
  static final StreamResolver _instance = StreamResolver._internal();
  factory StreamResolver() => _instance;
  StreamResolver._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, ResolvedStream> _cache = {};
  final Map<String, String> _resolvedVideoIds = {};

  static const MethodChannel _nativeChannel = MethodChannel('com.shreyx.player/native_stream');

  static const List<String> _invidiousInstances = [
    'https://invidious.f5.si',
  ];

  Future<T> _retryWithBackoff<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      attempt++;
      try {
        return await fn();
      } catch (e) {
        if (attempt >= maxAttempts) {
          debugPrint('[StreamResolver] Attempt $attempt failed. Max attempts reached. Throwing last error...');
          rethrow;
        }
        debugPrint('[StreamResolver] Attempt $attempt failed: $e. Retrying in ${delay.inMilliseconds}ms...');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  void clearCache() {
    _cache.clear();
    _resolvedVideoIds.clear();
    debugPrint('[StreamResolver] 🧹 Stream cache cleared.');
  }

  Future<bool> isStreamValid(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  Future<ResolvedStream?> _resolveNative(Stem stem) async {
    if (!Platform.isAndroid) return null;
    try {
      debugPrint('[StreamResolver] Attempting native NewPipe extraction for "${stem.title}" (${stem.sourceId})...');
      final dynamic res = await _nativeChannel.invokeMethod('resolveYouTubeStream', {
        'videoId': stem.sourceId,
      });
      if (res is Map && res['ok'] == true) {
        final url = res['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final dur = (res['durationSeconds'] as num?)?.toInt() ?? stem.durationSec;
          final ua = res['userAgent']?.toString() ??
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
          debugPrint('[StreamResolver] 🚀 Native NewPipe resolved successfully: "${stem.title}"');
          return ResolvedStream(
            uri: url,
            durationSec: dur > 0 ? dur : stem.durationSec,
            expiresAt: DateTime.now().add(const Duration(hours: 4)),
            resolvedVia: 'native_newpipe',
            effectiveStem: stem,
            userAgent: ua,
          );
        }
      } else if (res is Map) {
        debugPrint('[StreamResolver] Native NewPipe failed: ${res['message']}');
      }
    } catch (e) {
      debugPrint('[StreamResolver] Native NewPipe invocation error: $e');
    }
    return null;
  }

  Future<ResolvedStream> resolveStream(Stem stem) async {
    // 0. Check if stem has local file (instant 0ms)
    if (stem.isLocal && stem.localFilePath != null) {
      return ResolvedStream(
        uri: stem.localFilePath!,
        durationSec: stem.durationSec,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        resolvedVia: 'local_storage',
        effectiveStem: stem,
      );
    }

    // 1. Check memory stream cache (instant 0ms)
    final cached = _cache[stem.id];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached;
    } else if (cached != null) {
      // Expired - remove from cache and re-resolve
      _cache.remove(stem.id);
      debugPrint('[StreamResolver] ⏰ Expired cache entry for "${stem.title}", re-resolving...');
    }

    Stem effectiveStem = stem;

    // 2. Check if we already cached a YouTube video ID for this stem
    if (_resolvedVideoIds.containsKey(stem.id)) {
      effectiveStem = effectiveStem.copyWith(sourceId: _resolvedVideoIds[stem.id]!);
    }

    // 3. If sourceId is not an 11-char YouTube ID, search YouTube
    if (effectiveStem.sourceId.length != 11 ||
        effectiveStem.sourceId.contains(' ') ||
        effectiveStem.sourceId.startsWith('spot_')) {
      final rawQuery = '${stem.title} ${stem.artistName} official audio';
      final cleanQuery = rawQuery
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'[,|\\/_-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      String? resolvedVid;
      String? resolvedThumb;
      int? resolvedDur;

      // 3a. Prioritize YouTube Explode search for studio master
      try {
        final searchHits = await _yt.search.search(cleanQuery).timeout(const Duration(milliseconds: 3000));
        if (searchHits.isNotEmpty) {
          final top = searchHits.first;
          resolvedVid = top.id.value;
          resolvedThumb = top.thumbnails.highResUrl;
          resolvedDur = top.duration?.inSeconds;
        }
      } catch (_) {
        // Fallback without "official audio" tag
        try {
          final fallbackQuery = '${stem.title} ${stem.artistName}'.trim();
          final fallbackHits = await _yt.search.search(fallbackQuery).timeout(const Duration(milliseconds: 3000));
          if (fallbackHits.isNotEmpty) {
            final top = fallbackHits.first;
            resolvedVid = top.id.value;
            resolvedThumb = top.thumbnails.highResUrl;
            resolvedDur = top.duration?.inSeconds;
          }
        } catch (_) {}
      }

      if (resolvedVid != null && resolvedVid.length == 11) {
        _resolvedVideoIds[stem.id] = resolvedVid;
        final bool needsPoster = stem.artworkUrl.isEmpty ||
            stem.artworkUrl == stem.playlistArtwork ||
            stem.artworkUrl.contains('mosaic');
        final newArtwork = needsPoster && resolvedThumb != null ? resolvedThumb : stem.artworkUrl;

        effectiveStem = stem.copyWith(
          sourceId: resolvedVid,
          durationSec: stem.durationSec > 0 ? stem.durationSec : (resolvedDur ?? 180),
          artworkUrl: newArtwork,
        );
      } else {
        throw Exception('Could not find YouTube track matching "${stem.title}".');
      }
    }

    // 4. Try Android-native NewPipe Extractor (direct, unthrottled, studio quality)
    if (Platform.isAndroid &&
        effectiveStem.sourceId.length == 11 &&
        !effectiveStem.sourceId.contains(' ')) {
      final nativeRes = await _resolveNative(effectiveStem);
      if (nativeRes != null) {
        _cache[stem.id] = nativeRes;
        return nativeRes;
      }
    }

    // 5. Direct YoutubeExplode extraction with high-fidelity Opus stream selection
    try {
      final directRes = await _retryWithBackoff(() => _resolveYoutubeExplode(effectiveStem));
      _cache[stem.id] = directRes;
      return directRes;
    } catch (e) {
      debugPrint('[StreamResolver] Direct YoutubeExplode failed after retries ($e), trying fallback instances...');
    }

    // 6. Emergency Fallback: Invidious instances if direct extraction fails
    for (final host in _invidiousInstances) {
      try {
        final invRes = await _retryWithBackoff(() => _resolveInvidious(effectiveStem, host));
        _cache[stem.id] = invRes;
        return invRes;
      } catch (_) {}
    }

    throw Exception('Unable to resolve playable high-fidelity audio for "${stem.title}".');
  }

  Future<ResolvedStream> _resolveYoutubeExplode(Stem stem) async {
    final manifest = await _yt.videos.streamsClient
        .getManifest(stem.sourceId)
        .timeout(const Duration(milliseconds: 4000));
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) throw Exception('No audio streams available');

    // Prioritize high-fidelity Opus (typically ~160kbps, lossless perceptual quality)
    final sortedAudio = audioStreams.toList()..sort((a, b) {
      final aIsOpus = a.codec.mimeType.contains('webm') || a.codec.mimeType.contains('opus');
      final bIsOpus = b.codec.mimeType.contains('webm') || b.codec.mimeType.contains('opus');
      if (aIsOpus && !bIsOpus && a.bitrate.kiloBitsPerSecond >= 120) return -1;
      if (!aIsOpus && bIsOpus && b.bitrate.kiloBitsPerSecond >= 120) return 1;
      return b.bitrate.compareTo(a.bitrate);
    });

    final bestAudio = sortedAudio.first;
    debugPrint('[StreamResolver] 🎵 High-fidelity stream chosen: ${bestAudio.codec.mimeType} @ ${bestAudio.bitrate.kiloBitsPerSecond} kbps');

    return ResolvedStream(
      uri: bestAudio.url.toString(),
      durationSec: stem.durationSec > 0 ? stem.durationSec : bestAudio.size.totalBytes ~/ 16000,
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
      resolvedVia: 'youtube_explode_dart',
      effectiveStem: stem,
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    );
  }

  Future<ResolvedStream> _resolveInvidious(Stem stem, String host) async {
    final targetUrl = Uri.parse('$host/api/v1/videos/${stem.sourceId}');
    final res = await http.get(targetUrl, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-S921E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36'
    }).timeout(const Duration(milliseconds: 3500));
    if (res.statusCode != 200) throw Exception('Failed HTTP ${res.statusCode}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final formats = (data['adaptiveFormats'] as List<dynamic>?) ?? [];
    final audioFormats = formats.where((f) {
      final type = f['type']?.toString() ?? f['mimeType']?.toString() ?? '';
      return type.contains('audio') && f['url'] != null;
    }).toList();

    if (audioFormats.isEmpty) throw Exception('No audio formats');

    audioFormats.sort((a, b) {
      final bBitrate = int.tryParse(b['bitrate']?.toString() ?? '0') ?? 0;
      final aBitrate = int.tryParse(a['bitrate']?.toString() ?? '0') ?? 0;
      return bBitrate.compareTo(aBitrate);
    });

    final best = audioFormats.first;
    return ResolvedStream(
      uri: best['url'].toString(),
      durationSec: stem.durationSec > 0 ? stem.durationSec : (data['lengthSeconds'] as int? ?? 180),
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
      resolvedVia: 'proxy:$host',
      effectiveStem: stem,
    );
  }

  void dispose() {
    _yt.close();
  }
}
