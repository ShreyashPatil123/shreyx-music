import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/playlist.dart' as app_model;
import '../models/stem.dart';

enum LinkResultType { track, playlist }

class ResolvedLinkResult {
  final LinkResultType type;
  final Stem? track;
  final app_model.Playlist? playlist;
  final String originalUrl;

  ResolvedLinkResult.track(this.track, {required this.originalUrl})
      : type = LinkResultType.track,
        playlist = null;

  ResolvedLinkResult.playlist(this.playlist, {required this.originalUrl})
      : type = LinkResultType.playlist,
        track = null;

  String get title => type == LinkResultType.track ? (track?.title ?? '') : (playlist?.name ?? '');
  String get subtitle => type == LinkResultType.track
      ? (track?.artistName ?? '')
      : '${playlist?.stems.length ?? 0} tracks';
  String get artworkUrl =>
      type == LinkResultType.track ? (track?.artworkUrl ?? '') : (playlist?.artworkUrl ?? '');
}

class LinkResolverService {
  static final LinkResolverService _instance = LinkResolverService._internal();
  factory LinkResolverService() => _instance;
  LinkResolverService._internal();

  final YoutubeExplode _yt = YoutubeExplode();

  bool isSupported(String input) {
    final raw = input.trim().toLowerCase();
    return raw.contains('spotify.com') ||
        raw.contains('spotify.link') ||
        raw.startsWith('spotify:') ||
        raw.contains('youtube.com') ||
        raw.contains('youtu.be');
  }

  Future<ResolvedLinkResult> resolve(String rawUrl) async {
    String url = rawUrl.trim();
    if (url.isEmpty) throw Exception('Empty URL provided');

    // Handle spotify:track:... or spotify:playlist:...
    if (url.startsWith('spotify:')) {
      final parts = url.split(':');
      if (parts.length >= 3) {
        url = 'https://open.spotify.com/${parts[1]}/${parts[2]}';
      }
    }

    // 1. Spotify
    if (url.contains('spotify.com') || url.contains('spotify.link')) {
      return _resolveSpotify(url);
    }

    // 2. YouTube
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return _resolveYouTube(url);
    }

    throw Exception('Unsupported audio link. Please paste a Spotify or YouTube link.');
  }

  Future<ResolvedLinkResult> _resolveSpotify(String url) async {
    // Check if Single Spotify Track
    final trackMatch = RegExp(r'/track/([a-zA-Z0-9]+)').firstMatch(url);
    if (trackMatch != null) {
      final trackId = trackMatch.group(1)!;

      // 1. Fetch oEmbed for quick title & high-res artwork
      String title = '';
      String artworkUrl = '';
      try {
        final oembedUri =
            Uri.parse('https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}');
        final oembedRes = await http.get(oembedUri).timeout(const Duration(seconds: 4));
        if (oembedRes.statusCode == 200) {
          final data = jsonDecode(oembedRes.body) as Map<String, dynamic>;
          title = data['title'] as String? ?? '';
          artworkUrl = data['thumbnail_url'] as String? ?? '';
        }
      } catch (_) {}

      // 2. Fetch Embed HTML to get artist name
      String artistName = 'Spotify Artist';
      try {
        final embedUri = Uri.parse('https://open.spotify.com/embed/track/$trackId');
        final embedRes = await http.get(embedUri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }).timeout(const Duration(seconds: 4));

        if (embedRes.statusCode == 200) {
          final html = embedRes.body;
          final match = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>').firstMatch(html);
          if (match != null) {
            final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
            final entity = json['props']?['pageProps']?['state']?['data']?['entity'];
            if (entity != null) {
              if (title.isEmpty) title = entity['name'] ?? '';
              final artists = (entity['artists'] as List<dynamic>?)
                  ?.map((a) => a['name']?.toString() ?? '')
                  .where((n) => n.isNotEmpty)
                  .join(', ');
              if (artists != null && artists.isNotEmpty) {
                artistName = artists;
              }
            }
          }
        }
      } catch (_) {}

      if (title.isEmpty) title = 'Spotify Track';

      // 3. Search YouTube to find the best playable stream
      String sourceId = 'spot_$trackId';
      int durationSec = 180;
      try {
        final searchHits = await _yt.search.search('$title $artistName').timeout(const Duration(seconds: 5));
        if (searchHits.isNotEmpty) {
          final best = searchHits.first;
          sourceId = best.id.value;
          durationSec = best.duration?.inSeconds ?? 180;
          if (artworkUrl.isEmpty) {
            artworkUrl = best.thumbnails.highResUrl;
          }
        }
      } catch (_) {}

      final stem = Stem(
        id: 'spot_$trackId',
        title: title,
        artistName: artistName,
        artworkUrl: artworkUrl,
        durationSec: durationSec,
        sourceId: sourceId,
        albumName: 'Spotify Import',
      );

      return ResolvedLinkResult.track(stem, originalUrl: url);
    }

    // Check if Spotify Playlist or Album
    final playlistMatch = RegExp(r'/(playlist|album)/([a-zA-Z0-9]+)').firstMatch(url);
    if (playlistMatch != null) {
      final type = playlistMatch.group(1)!;
      final id = playlistMatch.group(2)!;

      final embedUri = Uri.parse('https://open.spotify.com/embed/$type/$id');
      final embedRes = await http.get(embedUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 6));

      if (embedRes.statusCode != 200) {
        throw Exception('Unable to load Spotify $type. Please ensure it is public.');
      }

      final html = embedRes.body;
      final match = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>').firstMatch(html);
      if (match == null) {
        throw Exception('Could not extract Spotify $type tracks.');
      }

      final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final entity = json['props']?['pageProps']?['state']?['data']?['entity'];
      if (entity == null) {
        throw Exception('Spotify $type contains no playable tracks.');
      }

      final plTitle = entity['name']?.toString() ?? (type == 'album' ? 'Spotify Album' : 'Spotify Playlist');
      final author = entity['subtitle']?.toString() ?? 'Spotify Curator';
      final artworkUrl = (entity['coverArt']?['sources'] as List<dynamic>?)?.firstOrNull?['url']?.toString() ??
          (entity['visualIdentity']?['image'] as List<dynamic>?)?.firstOrNull?['url']?.toString() ??
          '';

      final rawTracks = (entity['trackList'] as List<dynamic>?) ?? [];
      final List<Stem> stems = [];

      // Fetch distinct track posters in chunks of 5 using iTunes studio art + Spotify oEmbed fallback
      Future<String?> fetchTrackPoster(String title, String artist, String? uri) async {
        try {
          final cleanT = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceAll('\u00a0', ' ').trim();
          final cleanA = artist.replaceAll('\u00a0', ' ').trim();
          final q = '$cleanT $cleanA'.trim();
          final itunesUri = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(q)}&entity=song&limit=1');
          final res = await http.get(itunesUri).timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final results = data['results'] as List<dynamic>?;
            if (results != null && results.isNotEmpty) {
              final art100 = results.first['artworkUrl100']?.toString();
              if (art100 != null && art100.isNotEmpty) {
                return art100.replaceAll('100x100bb.jpg', '600x600bb.jpg');
              }
            }
          }
        } catch (_) {}

        if (uri != null && uri.contains(':track:')) {
          final trackId = uri.split(':').last;
          try {
            final res = await http.get(
              Uri.parse('https://open.spotify.com/oembed?url=https://open.spotify.com/track/$trackId'),
            ).timeout(const Duration(seconds: 2));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              final thumb = data['thumbnail_url']?.toString();
              if (thumb != null && thumb.isNotEmpty) return thumb;
            }
          } catch (_) {}
        }
        return null;
      }

      final List<String?> posters = List.filled(rawTracks.length, null);
      for (int i = 0; i < rawTracks.length; i += 5) {
        final end = (i + 5 > rawTracks.length) ? rawTracks.length : i + 5;
        final batch = <Future<void>>[];
        for (int j = i; j < end; j++) {
          final t = rawTracks[j];
          final rawTrackName = t['title']?.toString() ?? '';
          final rawTrackArtist = t['subtitle']?.toString() ?? author;
          final uri = t['uri']?.toString();
          batch.add(() async {
            posters[j] = await fetchTrackPoster(rawTrackName, rawTrackArtist, uri);
          }());
        }
        await Future.wait(batch);
      }

      for (int i = 0; i < rawTracks.length; i++) {
        final t = rawTracks[i];
        final rawTrackName = t['title']?.toString() ?? 'Track ${i + 1}';
        final rawTrackArtist = t['subtitle']?.toString() ?? author;
        final cleanTrackName = rawTrackName.replaceAll('\u00a0', ' ').trim();
        final cleanTrackArtist = rawTrackArtist.replaceAll('\u00a0', ' ').trim();
        final durMs = (t['duration'] as num?)?.toInt() ?? 180000;
        final trackArt = posters[i] ?? artworkUrl;

        stems.add(Stem(
          id: 'spot_${id}_$i',
          title: cleanTrackName,
          artistName: cleanTrackArtist,
          artworkUrl: trackArt,
          durationSec: durMs ~/ 1000,
          sourceId: '$cleanTrackName $cleanTrackArtist',
          albumName: plTitle,
          playlistId: 'pl_spot_$id',
          playlistTitle: plTitle,
          playlistArtwork: artworkUrl,
          spotifyUri: t['uri']?.toString(),
        ));
      }

      final playlist = app_model.Playlist(
        id: 'pl_spot_$id',
        name: plTitle,
        description: 'Imported Spotify $type by $author (${stems.length} tracks)',
        artworkUrl: artworkUrl,
        stems: stems,
      );

      return ResolvedLinkResult.playlist(playlist, originalUrl: url);
    }

    throw Exception('Unrecognized Spotify URL. Supported: /track, /playlist, or /album links.');
  }

  Future<ResolvedLinkResult> _resolveYouTube(String url) async {
    // 1. YouTube Playlist
    final listMatch = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (listMatch != null) {
      final listId = listMatch.group(1)!;

      try {
        final ytPlaylist = await _yt.playlists.get(listId).timeout(const Duration(seconds: 6));
        final plTitle = ytPlaylist.title;
        final author = ytPlaylist.author;
        final artworkUrl = ytPlaylist.thumbnails.highResUrl;

        final List<Stem> stems = [];
        final videoStream = _yt.playlists.getVideos(listId);

        await for (final video in videoStream.take(100)) {
          stems.add(Stem(
            id: 'yt_${video.id.value}',
            title: video.title,
            artistName: video.author,
            artworkUrl: video.thumbnails.standardResUrl.isNotEmpty
                ? video.thumbnails.standardResUrl
                : video.thumbnails.highResUrl,
            durationSec: video.duration?.inSeconds ?? 0,
            sourceId: video.id.value,
            albumName: plTitle,
            playlistId: 'pl_yt_$listId',
            playlistTitle: plTitle,
            playlistArtwork: artworkUrl,
          ));
        }

        final playlist = app_model.Playlist(
          id: 'pl_yt_$listId',
          name: plTitle,
          description: 'Imported YouTube playlist by $author (${stems.length} tracks)',
          artworkUrl: artworkUrl,
          stems: stems,
        );

        return ResolvedLinkResult.playlist(playlist, originalUrl: url);
      } catch (e) {
        throw Exception('Failed to load YouTube playlist: $e');
      }
    }

    // 2. Single YouTube Video
    String? videoId;
    final vMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (vMatch != null) {
      videoId = vMatch.group(1);
    } else {
      final shortMatch = RegExp(r'youtu.be/([a-zA-Z0-9_-]{11})').firstMatch(url);
      if (shortMatch != null) {
        videoId = shortMatch.group(1);
      }
    }

    if (videoId != null) {
      try {
        final video = await _yt.videos.get(videoId).timeout(const Duration(seconds: 5));
        final stem = Stem(
          id: 'yt_${video.id.value}',
          title: video.title,
          artistName: video.author,
          artworkUrl: video.thumbnails.highResUrl.isNotEmpty
              ? video.thumbnails.highResUrl
              : video.thumbnails.standardResUrl,
          durationSec: video.duration?.inSeconds ?? 0,
          sourceId: video.id.value,
          albumName: 'YouTube Import',
        );

        return ResolvedLinkResult.track(stem, originalUrl: url);
      } catch (e) {
        // Fallback synthetic stem
        final stem = Stem(
          id: 'yt_$videoId',
          title: 'YouTube Audio',
          artistName: 'YouTube',
          artworkUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
          durationSec: 180,
          sourceId: videoId,
          albumName: 'YouTube Import',
        );
        return ResolvedLinkResult.track(stem, originalUrl: url);
      }
    }

    throw Exception('Unrecognized YouTube URL format.');
  }

  void dispose() {
    _yt.close();
  }
}
