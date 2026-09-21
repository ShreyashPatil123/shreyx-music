import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/services/fast_downloader.dart';

void main() {
  late HttpServer testServer;
  late Uint8List dummyMediaData;
  late String serverUrl;

  setUpAll(() async {
    // Generate 3.5 MB of deterministic dummy audio data
    final length = (3.5 * 1024 * 1024).toInt();
    dummyMediaData = Uint8List(length);
    for (int i = 0; i < length; i++) {
      dummyMediaData[i] = i % 256;
    }

    testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverUrl = 'http://${testServer.address.address}:${testServer.port}/audio.m4a?clen=$length';

    testServer.listen((HttpRequest request) {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring(6).split('-');
        final start = int.parse(parts[0]);
        final end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1])
            : dummyMediaData.length - 1;

        final chunkData = dummyMediaData.sublist(start, end + 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${dummyMediaData.length}');
        request.response.headers.set(HttpHeaders.contentLengthHeader, chunkData.length.toString());
        request.response.add(chunkData);
        request.response.close();
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentLengthHeader, dummyMediaData.length.toString());
        request.response.add(dummyMediaData);
        request.response.close();
      }
    });
  });

  tearDownAll(() async {
    await testServer.close(force: true);
  });

  test('FastDownloader downloads 3.5MB file with parallel chunks and exact data match', () async {
    final tempDir = Directory.systemTemp.createTempSync('fast_dl_test_');
    final targetPath = '${tempDir.path}/downloaded.m4a';

    final progressUpdates = <double>[];

    final downloadedBytes = await FastDownloader.download(
      url: serverUrl,
      destinationPath: targetPath,
      chunkSize: 1024 * 1024, // 1MB chunks
      concurrency: 3,
      onProgress: (prog, received, total) {
        progressUpdates.add(prog);
      },
    );

    expect(downloadedBytes, equals(dummyMediaData.length));
    final resultFile = File(targetPath);
    expect(resultFile.existsSync(), isTrue);
    expect(resultFile.lengthSync(), equals(dummyMediaData.length));

    // Verify bit-for-bit data integrity
    final fileBytes = resultFile.readAsBytesSync();
    expect(fileBytes, equals(dummyMediaData));

    // Verify progress updates occurred and ended at 1.0
    expect(progressUpdates.isNotEmpty, isTrue);
    expect(progressUpdates.last, equals(1.0));

    tempDir.deleteSync(recursive: true);
  });

  test('FastDownloader handles cancellation cleanly and cleans temporary files', () async {
    final tempDir = Directory.systemTemp.createTempSync('fast_dl_cancel_');
    final targetPath = '${tempDir.path}/cancelled.m4a';

    bool cancelled = false;

    try {
      await FastDownloader.download(
        url: serverUrl,
        destinationPath: targetPath,
        chunkSize: 512 * 1024,
        concurrency: 2,
        isCancelled: () => cancelled,
        onProgress: (prog, received, total) {
          if (prog > 0.1) {
            cancelled = true;
          }
        },
      );
      fail('Should have thrown on cancellation');
    } catch (e) {
      expect(e.toString(), contains('cancelled'));
    }

    final targetFile = File(targetPath);
    expect(targetFile.existsSync(), isFalse);

    // Verify no stray .part files remain
    final partFiles = tempDir.listSync().where((f) => f.path.contains('.part_')).toList();
    expect(partFiles, isEmpty);

    tempDir.deleteSync(recursive: true);
  });
}
