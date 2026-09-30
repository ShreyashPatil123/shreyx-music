/// Normalizes song titles by stripping non-essential broadcast labels
/// while carefully preserving artistic descriptors (Remix, Live, Acoustic, etc.).
class MusicTitleNormalizer {
  static final RegExp _junkPatterns = RegExp(
    r'\b(full\s+video\s+song|full\s+audio\s+song|official\s+music\s+video|official\s+video|official\s+audio|music\s+video|lyric\s+video|lyrics\s+video|visualizer|audio|video|lyrics|full\s+song|full\s+video|remastered|remaster|4k|hd|1080p|hq|dolby\s+atmos|spatial\s+audio)\b',
    caseSensitive: false,
  );

  static final List<String> preservedDescriptors = [
    'remix',
    'live',
    'acoustic',
    'cover',
    'instrumental',
    'slowed',
    'reverb',
    'extended',
    'sped up',
    'unplugged',
    'piano version',
    'orchestral',
    'radio edit',
  ];

  /// Normalizes a song title for fair string and semantic matching.
  static String normalize(String title) {
    if (title.isEmpty) return '';

    String cleaned = title.replaceAll('\u00a0', ' ');

    // Match and process bracketed content [ ... ] or ( ... )
    cleaned = cleaned.replaceAllMapped(RegExp(r'[\(\[\{](.*?)[\)\]\}]'), (match) {
      final inner = match.group(1) ?? '';
      final lowerInner = inner.toLowerCase();

      // If the bracketed text contains a preserved descriptor (like "Live" or "Acoustic Remix"), keep it
      for (final desc in preservedDescriptors) {
        if (lowerInner.contains(desc)) {
          // Strip any junk keywords within the descriptor bracket
          final pruned = inner.replaceAll(_junkPatterns, '').replaceAll(RegExp(r'\s+'), ' ').trim();
          return pruned.isNotEmpty ? ' ($pruned)' : '';
        }
      }

      // If it only contains junk labels like "Official Video", remove entirely
      return '';
    });

    // Remove remaining junk words outside brackets
    cleaned = cleaned.replaceAll(_junkPatterns, ' ');

    // Clean repeated/consecutive delimiters (e.g. "| |" or "- |")
    cleaned = cleaned.replaceAll(RegExp(r'(\s*[-|/\\~•]\s*){2,}'), ' | ');

    // Clean dangling hyphens, pipes, slashes, and redundant spaces
    cleaned = cleaned
        .replaceAll(RegExp(r'\s*[-|/\\~•]\s*$'), '')
        .replaceAll(RegExp(r'^\s*[-|/\\~•]\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.isNotEmpty ? cleaned : title.trim();
  }

  /// Extracts any preserved descriptors found in [title] (e.g. ['acoustic', 'live']).
  static List<String> extractDescriptors(String title) {
    final lower = title.toLowerCase();
    final List<String> found = [];
    for (final desc in preservedDescriptors) {
      if (lower.contains(desc)) {
        found.add(desc);
      }
    }
    return found;
  }
}
