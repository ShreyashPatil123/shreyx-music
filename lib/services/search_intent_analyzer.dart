enum QueryIntentType {
  song,
  songAndArtist,
  variant,
  longForm,
}

class SearchIntent {
  final String rawQuery;
  final QueryIntentType type;
  final String normalizedQuery;
  final List<String> requestedVariants;
  final bool isExplicitLongForm;

  SearchIntent({
    required this.rawQuery,
    required this.type,
    required this.normalizedQuery,
    required this.requestedVariants,
    required this.isExplicitLongForm,
  });
}

/// Analyzes user search queries to distinguish standard song searches from explicit mixes.
class SearchIntentAnalyzer {
  static final RegExp _longFormKeywords = RegExp(
    r'\b(mix|playlist|compilation|nonstop|non-stop|mega\s*mix|medley|mashup|live\s*set|set|dj\s*mix|1\s*hour|2\s*hours|workout\s*mix|study\s*music|chill\s*mix|lofi\s*mix)\b',
    caseSensitive: false,
  );

  static final List<String> _variantKeywords = [
    'remix',
    'live',
    'acoustic',
    'cover',
    'instrumental',
    'slowed',
    'reverb',
    'extended',
    'sped up',
    'piano',
    'orchestral',
    'unplugged',
  ];

  /// Classifies [query] and detects explicit user intent.
  static SearchIntent analyze(String query) {
    final clean = query.trim();
    final lower = clean.toLowerCase();

    // Check for explicit long-form intent
    final bool hasLongFormKeyword = _longFormKeywords.hasMatch(lower);

    // Check for requested variants
    final List<String> foundVariants = [];
    for (final v in _variantKeywords) {
      if (lower.contains(v)) {
        foundVariants.add(v);
      }
    }

    QueryIntentType type;
    if (hasLongFormKeyword) {
      type = QueryIntentType.longForm;
    } else if (foundVariants.isNotEmpty) {
      type = QueryIntentType.variant;
    } else if (clean.contains(' - ') || clean.split(' ').length >= 3) {
      type = QueryIntentType.songAndArtist;
    } else {
      type = QueryIntentType.song;
    }

    return SearchIntent(
      rawQuery: clean,
      type: type,
      normalizedQuery: lower,
      requestedVariants: foundVariants,
      isExplicitLongForm: hasLongFormKeyword,
    );
  }
}
