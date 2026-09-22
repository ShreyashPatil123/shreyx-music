class Stem {
  final String id;
  final String title;
  final String artistName;
  final String artworkUrl;
  final int durationSec;
  final String sourceId;
  final String? albumName;
  String? streamUri;
  String? localFilePath;
  String? playlistId;
  String? playlistTitle;
  String? playlistArtwork;
  int? fileSizeBytes;
  String? spotifyUri;

  Stem({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artworkUrl,
    required this.durationSec,
    required this.sourceId,
    this.albumName,
    this.streamUri,
    this.localFilePath,
    this.playlistId,
    this.playlistTitle,
    this.playlistArtwork,
    this.fileSizeBytes,
    this.spotifyUri,
  });

  bool get isLocal => localFilePath != null && localFilePath!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artistName': artistName,
        'artworkUrl': artworkUrl,
        'durationSec': durationSec,
        'sourceId': sourceId,
        'albumName': albumName,
        'streamUri': streamUri,
        'localFilePath': localFilePath,
        'playlistId': playlistId,
        'playlistTitle': playlistTitle,
        'playlistArtwork': playlistArtwork,
        'fileSizeBytes': fileSizeBytes,
        'spotifyUri': spotifyUri,
      };

  factory Stem.fromJson(Map<String, dynamic> json) => Stem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Unknown Track',
        artistName: json['artistName']?.toString() ?? 'Unknown Artist',
        artworkUrl: json['artworkUrl']?.toString() ?? '',
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        sourceId: json['sourceId']?.toString() ?? '',
        albumName: json['albumName']?.toString(),
        streamUri: json['streamUri']?.toString(),
        localFilePath: json['localFilePath']?.toString(),
        playlistId: json['playlistId']?.toString(),
        playlistTitle: json['playlistTitle']?.toString(),
        playlistArtwork: json['playlistArtwork']?.toString(),
        fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
        spotifyUri: json['spotifyUri']?.toString(),
      );

  Stem copyWith({
    String? id,
    String? title,
    String? artistName,
    String? artworkUrl,
    int? durationSec,
    String? sourceId,
    String? albumName,
    String? streamUri,
    String? localFilePath,
    String? playlistId,
    String? playlistTitle,
    String? playlistArtwork,
    int? fileSizeBytes,
    String? spotifyUri,
  }) {
    return Stem(
      id: id ?? this.id,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      durationSec: durationSec ?? this.durationSec,
      sourceId: sourceId ?? this.sourceId,
      albumName: albumName ?? this.albumName,
      streamUri: streamUri ?? this.streamUri,
      localFilePath: localFilePath ?? this.localFilePath,
      playlistId: playlistId ?? this.playlistId,
      playlistTitle: playlistTitle ?? this.playlistTitle,
      playlistArtwork: playlistArtwork ?? this.playlistArtwork,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      spotifyUri: spotifyUri ?? this.spotifyUri,
    );
  }
}
