class LyricLine {
  final int timeMs;
  final String text;

  LyricLine({required this.timeMs, required this.text});

  double get timeSec => timeMs / 1000.0;
}

class ParsedLyrics {
  final bool isSynced;
  final List<LyricLine> lines;
  final String? plainLyrics;

  ParsedLyrics({
    required this.isSynced,
    required this.lines,
    this.plainLyrics,
  });

  bool get isEmpty => lines.isEmpty && (plainLyrics == null || plainLyrics!.isEmpty);
}
