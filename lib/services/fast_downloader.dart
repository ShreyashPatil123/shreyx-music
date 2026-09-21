import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// High-speed multi-range chunked downloader.
///
/// YouTube and various CDNs artificially throttle single-stream HTTP requests
/// to playback bitrate (~24-40 KB/s). By requesting audio in 512KB-1MB byte
/// ranges across 3-4 parallel connections, every request hits the CDN's
/// unthrottled burst window, achieving download speeds 20x to 50x faster.
class FastDownloader {
  static const int defaultChunkSize = 1024 * 1024; // 1 MB chunks
  static const int defaultConcurrency = 3;         // 3 parallel connections
  static const int maxChunkRetries = 2;

  /// Downloads [url] to [destinationPath] using parallel Range requests.
  /// Returns the total bytes downloaded.
  static Future<int> download({
    required String url,
    required String destinationPath,
    String? userAgent,
    int chunkSize = defaultChunkSize,
    int concurrency = defaultConcurrency,
    bool Function()? isCancelled,
    void Function(double progress, int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    int totalBytes = -1;
    bool supportsRanges = false;

    // ── Step 1: Probe for Content-Length and Range support ──
    // Check if 'clen' is already in YouTube URL query params
    final clenMatch = RegExp(r'[?&]clen=(\d+)').firstMatch(url);
    if (clenMatch != null) {
      totalBytes = int.tryParse(clenMatch.group(1)!) ?? -1;
    }

    try {
      final probeReq = await client.getUrl(Uri.parse(url));
      if (userAgent != null && userAgent.isNotEmpty) {
        probeReq.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      probeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final probeResp = await probeReq.close();

      if (probeResp.statusCode == 206) {
        supportsRanges = true;
        final cr = probeResp.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null) {
          final match = RegExp(r'/(\d+)').firstMatch(cr);
          if (match != null) {
            totalBytes = int.tryParse(match.group(1)!) ?? totalBytes;
          }
        }
      } else if (probeResp.statusCode == 200) {
        // Server doesn't support ranges, but gave entire stream length
        supportsRanges = false;
        totalBytes = probeResp.contentLength;
      }
      // Drain probe response
      await probeResp.drain();
    } catch (e) {
      debugPrint('[FastDownloader] Probe notice: $e');
    }

    if (isCancelled?.call() == true) throw Exception('Download cancelled by user');

    // If ranges are not supported or file is small (<1.2MB), fallback to single stream
    if (!supportsRanges || totalBytes <= (chunkSize * 1.2)) {
      return await _downloadSingleStream(
        url: url,
        destinationPath: destinationPath,
        userAgent: userAgent,
        client: client,
        knownTotalBytes: totalBytes > 0 ? totalBytes : null,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
    }

    // ── Step 2: Plan byte-range chunks ──
    final List<_ChunkTask> chunks = [];
    int start = 0;
    int chunkIdx = 0;
    while (start < totalBytes) {
      final end = math.min(start + chunkSize - 1, totalBytes - 1);
      chunks.add(_ChunkTask(
        index: chunkIdx++,
        start: start,
        end: end,
        totalChunkBytes: end - start + 1,
      ));
      start = end + 1;
    }

    final chunkProgress = List<int>.filled(chunks.length, 0);
    int lastReportTime = 0;
    double lastReportProg = 0.0;

    void updateProgress() {
      if (onProgress == null) return;
      final totalReceived = chunkProgress.fold<int>(0, (sum, val) => sum + val);
      final prog = (totalReceived / totalBytes).clamp(0.0, 1.0);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (prog >= 1.0 || (now - lastReportTime) > 80 || (prog - lastReportProg).abs() >= 0.01) {
        lastReportTime = now;
        lastReportProg = prog;
        onProgress(prog, totalReceived, totalBytes);
      }
    }

    int nextChunkQueueIndex = 0;
    final List<String> partFiles = [];

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) throw Exception('Download cancelled by user');

        _ChunkTask task;
        // Grab next chunk
        if (nextChunkQueueIndex >= chunks.length) break;
        task = chunks[nextChunkQueueIndex++];

        final partPath = '$destinationPath.part_${task.index}';
        partFiles.add(partPath);

        int attempts = 0;
        bool success = false;
        while (attempts <= maxChunkRetries && !success) {
          if (isCancelled?.call() == true) throw Exception('Download cancelled by user');
          attempts++;
          try {
            final partFile = File(partPath);
            final chunkReq = await client.getUrl(Uri.parse(url));
            if (userAgent != null && userAgent.isNotEmpty) {
              chunkReq.headers.set(HttpHeaders.userAgentHeader, userAgent);
            }
            chunkReq.headers.set(HttpHeaders.rangeHeader, 'bytes=${task.start}-${task.end}');
            final chunkResp = await chunkReq.close();

            if (chunkResp.statusCode != 206 && chunkResp.statusCode != 200) {
              throw HttpException('HTTP ${chunkResp.statusCode}');
            }

            final sink = partFile.openWrite();
            int chunkReceived = 0;
            await for (final data in chunkResp) {
              if (isCancelled?.call() == true) {
                await sink.close();
                throw Exception('Download cancelled by user');
              }
              sink.add(data);
              chunkReceived += data.length;
              chunkProgress[task.index] = chunkReceived;
              updateProgress();
            }
            await sink.flush();
            await sink.close();

            if (partFile.lengthSync() == task.totalChunkBytes) {
              success = true;
            } else {
              throw Exception('Incomplete chunk size: expected ${task.totalChunkBytes}, got ${partFile.lengthSync()}');
            }
          } catch (err) {
            chunkProgress[task.index] = 0;
            updateProgress();
            if (attempts > maxChunkRetries) {
              rethrow;
            }
            await Future.delayed(Duration(milliseconds: 150 * attempts));
          }
        }
      }
    }

    try {
      final actualConcurrency = math.min(concurrency, chunks.length);
      await Future.wait(List.generate(actualConcurrency, (_) => worker()));

      if (isCancelled?.call() == true) throw Exception('Download cancelled by user');

      // ── Step 3: Assemble all chunk parts sequentially ──
      final finalFile = File(destinationPath);
      final finalSink = finalFile.openWrite();

      for (int i = 0; i < chunks.length; i++) {
        final partFile = File('$destinationPath.part_$i');
        if (!partFile.existsSync()) {
          throw Exception('Missing part file $i during assembly');
        }
        await finalSink.addStream(partFile.openRead());
      }
      await finalSink.flush();
      await finalSink.close();

      // Clean up part files
      for (int i = 0; i < chunks.length; i++) {
        try {
          final p = File('$destinationPath.part_$i');
          if (p.existsSync()) p.deleteSync();
        } catch (_) {}
      }

      onProgress?.call(1.0, totalBytes, totalBytes);
      return totalBytes;
    } catch (e) {
      // Clean up on failure
      for (final p in partFiles) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      try {
        final f = File(destinationPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Single connection streaming fallback
  static Future<int> _downloadSingleStream({
    required String url,
    required String destinationPath,
    required HttpClient client,
    String? userAgent,
    int? knownTotalBytes,
    bool Function()? isCancelled,
    void Function(double progress, int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final req = await client.getUrl(Uri.parse(url));
    if (userAgent != null && userAgent.isNotEmpty) {
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    final resp = await req.close();
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw HttpException('HTTP ${resp.statusCode}');
    }

    final totalBytes = knownTotalBytes ?? resp.contentLength;
    int receivedBytes = 0;
    int lastReport = 0;
    double lastProg = 0.0;

    final file = File(destinationPath);
    final sink = file.openWrite();

    try {
      await for (final chunk in resp) {
        if (isCancelled?.call() == true) {
          await sink.close();
          if (file.existsSync()) file.deleteSync();
          throw Exception('Download cancelled by user');
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (onProgress != null && totalBytes > 0) {
          final prog = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          final now = DateTime.now().millisecondsSinceEpoch;
          if (prog >= 1.0 || (now - lastReport) > 80 || (prog - lastProg).abs() >= 0.01) {
            lastReport = now;
            lastProg = prog;
            onProgress(prog, receivedBytes, totalBytes);
          }
        }
      }
      await sink.flush();
      await sink.close();

      onProgress?.call(1.0, receivedBytes, receivedBytes);
      return receivedBytes;
    } catch (e) {
      await sink.close();
      if (file.existsSync()) {
        try { file.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
  }
}

class _ChunkTask {
  final int index;
  final int start;
  final int end;
  final int totalChunkBytes;

  _ChunkTask({
    required this.index,
    required this.start,
    required this.end,
    required this.totalChunkBytes,
  });
}
