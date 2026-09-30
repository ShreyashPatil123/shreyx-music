import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stem.dart';
import 'network_identity_service.dart';
import 'playback_diagnostics_service.dart';
import 'prepared_track_cache.dart';
import 'stream_capability_selector.dart';

/// Authoritative stream resolution service implementing controlled fallback extraction (Safeguard 1).
class TrackPreparationService {
  static final TrackPreparationService _instance = TrackPreparationService._internal();
  factory TrackPreparationService() => _instance;
  TrackPreparationService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final PreparedTrackCache _cache = PreparedTrackCache();
  final StreamCapabilitySelector _capability = StreamCapabilitySelector();
  final NetworkIdentityService _identity = NetworkIdentityService();
  final PlaybackDiagnosticsService _diagnostics = PlaybackDiagnosticsService();

  static const MethodChannel _nativeChannel = MethodChannel('com.shreyx.player/native_stream');

  /// Timeout before starting the fallback resolver on Android if primary has not completed.
  static const Duration fallbackThreshold = Duration(milliseconds: 2500);

  /// Hard timeout for any single extraction attempt
  static const Duration maxExtractionTimeout = Duration(milliseconds: 6500);

  /// Monotonically increasing resolution token to detect and discard stale superseded requests.
  int _activeResolutionToken = 0;

  /// Cache of resolved YouTube video IDs for non-YouTube stems (e.g. Spotify tracks)
  final Map<String, String> _resolvedVideoIds = {};

  PreparedTrackCache get cache => _cache;

  /// Resolves a playable [PreparedTrack] for the given [stem].
  ///
  /// Enforces controlled fallback hedging, race-condition safety, and instant cache hit reuse.
  Future<PreparedTrack> prepareTrack(
    Stem stem, {
    String? diagnosticsSessionId,
  }) async {
    final int currentToken = ++_activeResolutionToken;

    // 0. Local file stem (instant 0ms)
    if (stem.isLocal && stem.localFilePath != null) {
      final localTrack = PreparedTrack(
        videoId: stem.sourceId,
        uri: stem.localFilePath!,
        codec: 'local',
        container: 'local',
        bitrate: 0,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        resolvedAt: DateTime.now(),
        resolver: 'local_storage',
        fileExtension: 'm4a',
        effectiveStem: stem,
      );
      if (diagnosticsSessionId != null) {
        _diagnostics.markStreamSelected(
          diagnosticsSessionId,
          resolver: 'local_storage',
          codec: 'local',
          wasCached: true,
        );
      }
      return localTrack;
    }

    Stem effectiveStem = stem;

    // 1. Resolve to valid 11-char YouTube video ID if needed
    if (_resolvedVideoIds.containsKey(stem.id)) {
      effectiveStem = effectiveStem.copyWith(sourceId: _resolvedVideoIds[stem.id]!);
    } else if (effectiveStem.sourceId.length != 11 ||
        effectiveStem.sourceId.contains(' ') ||
        effectiveStem.sourceId.startsWith('spot_')) {
      if (diagnosticsSessionId != null) {
        _diagnostics.markSearchToYouTubeResolution(diagnosticsSessionId);
      }
      final resolvedId = await _findYouTubeVideoId(effectiveStem);
      if (resolvedId != null) {
        _resolvedVideoIds[stem.id] = resolvedId;
        effectiveStem = effectiveStem.copyWith(sourceId: resolvedId);
      } else {
        throw Exception('Could not match YouTube track for "${stem.title}".');
      }
    }

    if (currentToken != _activeResolutionToken) {
      throw CancellationException('Track resolution superseded by user action');
    }

    final String videoId = effectiveStem.sourceId;

    // 2. Check in-memory PreparedTrackCache (instant hit)
    final cached = _cache.get(videoId);
    if (cached != null) {
      if (diagnosticsSessionId != null) {
        _diagnostics.markStreamSelected(
          diagnosticsSessionId,
          resolver: 'cache:${cached.resolver}',
          codec: cached.codec,
          container: cached.container,
          bitrate: cached.bitrate,
          wasCached: true,
        );
      }
      return cached;
    }

    // 3. Controlled Fallback Extraction Strategy
    PreparedTrack? resolvedTrack;

    if (!kIsWeb && Platform.isAndroid) {
      // Android: Native NewPipe is PRIMARY.
      // Launch Native NewPipe first.
      // Only if it exceeds fallbackThreshold (2.5s) without finishing, launch Dart fallback.
      resolvedTrack = await _resolveWithControlledFallback(
        effectiveStem,
        currentToken: currentToken,
        diagnosticsSessionId: diagnosticsSessionId,
      );
    } else {
      // iOS / Desktop / Web: Pure Dart cross-platform path is PRIMARY.
      if (diagnosticsSessionId != null) {
        _diagnostics.markDartStart(diagnosticsSessionId);
      }
      resolvedTrack = await _resolveDart(effectiveStem, diagnosticsSessionId: diagnosticsSessionId);
      if (diagnosticsSessionId != null) {
        _diagnostics.markDartComplete(diagnosticsSessionId);
      }
    }

    if (currentToken != _activeResolutionToken) {
      throw CancellationException('Track resolution superseded by user action');
    }

    if (resolvedTrack != null) {
      _cache.put(resolvedTrack);
      if (diagnosticsSessionId != null) {
        _diagnostics.markStreamSelected(
          diagnosticsSessionId,
          resolver: resolvedTrack.resolver,
          codec: resolvedTrack.codec,
          container: resolvedTrack.container,
          bitrate: resolvedTrack.bitrate,
          wasCached: false,
        );
      }
      return resolvedTrack;
    }

    throw Exception('Failed to resolve playable audio stream for "${stem.title}".');
  }

  /// Controlled fallback resolution on Android:
  /// Starts Primary (Native NewPipe). If unresolved after [fallbackThreshold], starts Fallback (Dart).
  /// First valid result wins; slower attempt is safely discarded.
  Future<PreparedTrack?> _resolveWithControlledFallback(
    Stem stem, {
    required int currentToken,
    String? diagnosticsSessionId,
  }) async {
    final completer = Completer<PreparedTrack?>();
    Timer? fallbackTimer;
    bool hasCompleted = false;

    void win(PreparedTrack track, String source) {
      if (!hasCompleted && currentToken == _activeResolutionToken) {
        hasCompleted = true;
        fallbackTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(track);
        }
      }
    }

    // 1. Start Primary (Native NewPipe)
    if (diagnosticsSessionId != null) {
      _diagnostics.markNativeStart(diagnosticsSessionId);
    }

    _resolveNative(stem).then((nativeTrack) {
      if (diagnosticsSessionId != null) {
        _diagnostics.markNativeComplete(diagnosticsSessionId);
      }
      if (nativeTrack != null) {
        win(nativeTrack, 'native');
      }
    }).catchError((e) {
      debugPrint('[TrackPreparation] Native resolver error: $e');
    });

    // 2. Start timer for Fallback (Dart)
    fallbackTimer = Timer(fallbackThreshold, () {
      if (!hasCompleted && currentToken == _activeResolutionToken) {
        debugPrint('[TrackPreparation] ⏱️ Primary resolution exceeded ${fallbackThreshold.inMilliseconds}ms. Starting Dart fallback...');
        if (diagnosticsSessionId != null) {
          _diagnostics.markDartStart(diagnosticsSessionId);
        }
        _resolveDart(stem, diagnosticsSessionId: diagnosticsSessionId).then((dartTrack) {
          if (diagnosticsSessionId != null) {
            _diagnostics.markDartComplete(diagnosticsSessionId);
          }
          if (dartTrack != null) {
            win(dartTrack, 'dart_fallback');
          }
        }).catchError((e) {
          debugPrint('[TrackPreparation] Dart fallback resolver error: $e');
        });
      }
    });

    // Hard ceiling timeout
    return Future.any([
      completer.future,
      Future.delayed(maxExtractionTimeout, () => null),
    ]);
  }

  /// Native NewPipe resolution via Android platform channel.
  Future<PreparedTrack?> _resolveNative(Stem stem) async {
    try {
      final dynamic res = await _nativeChannel.invokeMethod('resolveYouTubeStream', {
        'videoId': stem.sourceId,
      });

      if (res is Map && res['ok'] == true) {
        final url = res['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final mime = res['mimeType']?.toString() ?? 'audio/webm';
          final bitrate = (res['bitrate'] as num?)?.toInt() ?? 160000;
          final ua = res['userAgent']?.toString() ?? _identity.userAgent;
          final ext = _capability.determineFileExtension(mimeType: mime);

          return PreparedTrack(
            videoId: stem.sourceId,
            uri: url,
            codec: mime,
            container: ext,
            bitrate: bitrate,
            expiresAt: DateTime.now().add(const Duration(hours: 3)),
            resolvedAt: DateTime.now(),
            resolver: 'native_newpipe',
            fileExtension: ext,
            userAgent: ua,
            effectiveStem: stem,
          );
        }
      }
    } catch (e) {
      debugPrint('[TrackPreparation] Native invocation failed: $e');
    }
    return null;
  }

  /// Pure Dart YouTubeExplode resolution with cross-platform capability stream selection.
  Future<PreparedTrack?> _resolveDart(Stem stem, {String? diagnosticsSessionId}) async {
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(stem.sourceId)
          .timeout(const Duration(milliseconds: 4500));

      final selected = _capability.selectBestStream(manifest);
      if (selected != null) {
        return PreparedTrack(
          videoId: stem.sourceId,
          uri: selected.url.toString(),
          codec: selected.codec,
          container: selected.container,
          bitrate: selected.bitrate,
          expiresAt: DateTime.now().add(const Duration(hours: 3)),
          resolvedAt: DateTime.now(),
          resolver: 'youtube_explode_dart',
          fileExtension: selected.fileExtension,
          userAgent: _identity.userAgent,
          effectiveStem: stem,
        );
      }
    } catch (e) {
      debugPrint('[TrackPreparation] Dart extraction failed for ${stem.sourceId}: $e');
    }
    return null;
  }

  /// Searches YouTube to find the best 11-char video ID for Spotify / raw search stems.
  Future<String?> _findYouTubeVideoId(Stem stem) async {
    final cleanQuery = '${stem.title} ${stem.artistName}'
        .replaceAll(RegExp(r'[,|\\/_-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    try {
      final hits = await _yt.search.search('$cleanQuery official audio').timeout(const Duration(seconds: 3));
      if (hits.isNotEmpty) {
        return hits.first.id.value;
      }
    } catch (_) {}

    try {
      final fallbackHits = await _yt.search.search(cleanQuery).timeout(const Duration(seconds: 3));
      if (fallbackHits.isNotEmpty) {
        return fallbackHits.first.id.value;
      }
    } catch (_) {}

    return null;
  }

  void invalidateStream(String videoId) {
    _cache.invalidate(videoId);
  }

  void cancelActiveResolutions() {
    _activeResolutionToken++;
  }

  void dispose() {
    _yt.close();
  }
}

class CancellationException implements Exception {
  final String message;
  CancellationException(this.message);
  @override
  String toString() => 'CancellationException: $message';
}
