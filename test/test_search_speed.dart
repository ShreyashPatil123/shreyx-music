import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    final sw = Stopwatch()..start();
    print("Searching...");
    final hits = await yt.search.search("Ajab Si KK Vishal Shekhar");
    print("Search took: ${sw.elapsedMilliseconds} ms");
    if (hits.isNotEmpty) {
      print("Hit 1: ${hits.first.title} (${hits.first.id.value}) - ${hits.first.duration}");
    }
  } catch (e) {
    print("Search error: $e");
  } finally {
    yt.close();
  }
}
