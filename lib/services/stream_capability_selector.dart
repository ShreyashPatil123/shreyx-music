import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class SelectedStreamInfo {
  final Uri url;
  final String codec;
  final String container;
  final String mimeType;
  final int bitrate;
  final String fileExtension;
  final int? sizeBytes;

  SelectedStreamInfo({
    required this.url,
    required this.codec,
    required this.container,
    required this.mimeType,
    required this.bitrate,
    required this.fileExtension,
    this.sizeBytes,
  });
}

/// Centralized cross-platform audio stream capability selector.
///
/// Ensures Android receives optimal high-fidelity Opus/WebM streams, while
/// iOS/Apple devices strictly receive AAC/MP4/M4A streams that AVPlayer can demux.
class StreamCapabilitySelector {
  static final StreamCapabilitySelector _instance = StreamCapabilitySelector._internal();
  factory StreamCapabilitySelector() => _instance;
  StreamCapabilitySelector._internal();

  bool get isApple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Selects the best compatible stream from a YouTubeExplode [StreamManifest].
  SelectedStreamInfo? selectBestStream(StreamManifest manifest) {
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) return null;

    final sorted = sortAudioStreams(audioStreams.toList());
    if (sorted.isEmpty) return null;

    final best = sorted.first;
    final mime = best.codec.mimeType.toLowerCase();
    final containerName = best.container.name.toLowerCase();

    String ext = 'm4a';
    if (containerName.contains('webm') || mime.contains('webm') || mime.contains('opus')) {
      ext = 'webm';
    } else if (containerName.contains('mp4') || mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
      ext = 'm4a';
    }

    return SelectedStreamInfo(
      url: best.url,
      codec: best.codec.mimeType,
      container: best.container.name,
      mimeType: best.codec.mimeType,
      bitrate: best.bitrate.bitsPerSecond,
      fileExtension: ext,
      sizeBytes: best.size.totalBytes,
    );
  }

  /// Sorts audio stream infos according to platform compatibility rules.
  List<AudioStreamInfo> sortAudioStreams(List<AudioStreamInfo> streams) {
    final List<AudioStreamInfo> validStreams = streams.where((s) => s.url.toString().isNotEmpty).toList();
    if (validStreams.isEmpty) return [];

    validStreams.sort((a, b) {
      final aMime = a.codec.mimeType.toLowerCase();
      final bMime = b.codec.mimeType.toLowerCase();
      final aContainer = a.container.name.toLowerCase();
      final bContainer = b.container.name.toLowerCase();

      final aIsAppleCompatible = aContainer == 'mp4' || aMime.contains('mp4') || aMime.contains('m4a') || aMime.contains('aac');
      final bIsAppleCompatible = bContainer == 'mp4' || bMime.contains('mp4') || bMime.contains('m4a') || bMime.contains('aac');

      if (isApple) {
        // On iOS/macOS: AVPlayer requires AAC / MP4 / M4A containers.
        if (aIsAppleCompatible && !bIsAppleCompatible) return -1;
        if (!aIsAppleCompatible && bIsAppleCompatible) return 1;
        return b.bitrate.compareTo(a.bitrate);
      } else {
        // On Android: ExoPlayer natively decodes Opus in WebM.
        // Prefer Opus/WebM at >=120kbps (~160kbps studio master quality).
        final aIsOpus = aContainer.contains('webm') || aMime.contains('opus') || aMime.contains('webm');
        final bIsOpus = bContainer.contains('webm') || bMime.contains('opus') || bMime.contains('webm');

        if (aIsOpus && !bIsOpus && a.bitrate.kiloBitsPerSecond >= 120) return -1;
        if (!aIsOpus && bIsOpus && b.bitrate.kiloBitsPerSecond >= 120) return 1;
        return b.bitrate.compareTo(a.bitrate);
      }
    });

    return validStreams;
  }

  /// Computes the correct file extension for a given MIME type or container name.
  String determineFileExtension({String? mimeType, String? container}) {
    final m = (mimeType ?? '').toLowerCase();
    final c = (container ?? '').toLowerCase();
    if (m.contains('webm') || m.contains('opus') || c.contains('webm')) {
      return 'webm';
    }
    return 'm4a';
  }
}
