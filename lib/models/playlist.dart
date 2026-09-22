import 'stem.dart';

class Playlist {
  final String id;
  String name;
  String description;
  String artworkUrl;
  List<Stem> stems;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.artworkUrl = '',
    List<Stem>? stems,
    DateTime? createdAt,
  })  : stems = stems ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'artworkUrl': artworkUrl,
        'stems': stems.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawStems = json['stems'] as List<dynamic>? ?? [];
    final List<Stem> parsedStems = [];
    for (final s in rawStems) {
      if (s is Map<String, dynamic>) {
        try {
          parsedStems.add(Stem.fromJson(s));
        } catch (_) {}
      }
    }

    return Playlist(
      id: json['id']?.toString() ?? 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      description: json['description']?.toString() ?? '',
      artworkUrl: json['artworkUrl']?.toString() ?? '',
      stems: parsedStems,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class DownloadedPlaylistGroup {
  final String id;
  final String title;
  final String artworkUrl;
  final List<Stem> stems;
  final int totalSizeBytes;
  final bool isStandalone;

  DownloadedPlaylistGroup({
    required this.id,
    required this.title,
    required this.artworkUrl,
    required this.stems,
    required this.totalSizeBytes,
    required this.isStandalone,
  });

  double get sizeInMB => totalSizeBytes / (1024 * 1024);
}
