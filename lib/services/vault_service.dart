import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/stem.dart';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  final Map<String, Stem> _favorites = {};
  final List<Playlist> _playlists = [];
  Function()? onVaultChanged;

  static const String _favKey = 'shrex_favorites';
  static const String _playlistKey = 'shrex_playlists';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Favorites
    final favRaw = prefs.getString(_favKey);
    if (favRaw != null) {
      try {
        final list = jsonDecode(favRaw) as List<dynamic>;
        for (final item in list) {
          final stem = Stem.fromJson(item as Map<String, dynamic>);
          _favorites[stem.id] = stem;
        }
      } catch (_) {}
    }

    // Load Playlists
    final plRaw = prefs.getString(_playlistKey);
    if (plRaw != null) {
      try {
        final list = jsonDecode(plRaw) as List<dynamic>;
        _playlists.clear();
        for (final item in list) {
          _playlists.add(Playlist.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // Automatically upgrade any legacy mosaic posters in background
    upgradePlaylistPostersInBackground();
  }

  List<Stem> get favorites => _favorites.values.toList();
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  bool isFavorite(String stemId) => _favorites.containsKey(stemId);

  Future<void> toggleFavorite(Stem stem) async {
    if (_favorites.containsKey(stem.id)) {
      _favorites.remove(stem.id);
    } else {
      _favorites[stem.id] = stem;
    }
    await _saveFavorites();
  }

  Future<Playlist> createPlaylist(String name, {String description = '', List<Stem>? stems}) async {
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      artworkUrl: stems?.isNotEmpty == true ? stems!.first.artworkUrl : '',
      stems: stems ?? [],
    );
    _playlists.add(newPlaylist);
    await _savePlaylists();
    return newPlaylist;
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    await _savePlaylists();
  }

  Future<void> addStemToPlaylist(String playlistId, Stem stem) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final pl = _playlists[idx];
      if (!pl.stems.any((s) => s.id == stem.id)) {
        pl.stems.add(stem);
        if (pl.artworkUrl.isEmpty) {
          pl.artworkUrl = stem.artworkUrl;
        }
        await _savePlaylists();
      }
    }
  }

  Future<void> removeStemFromPlaylist(String playlistId, String stemId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx].stems.removeWhere((s) => s.id == stemId);
      await _savePlaylists();
    }
  }

  Future<void> updateStem(Stem stem) async {
    bool changed = false;
    if (_favorites.containsKey(stem.id)) {
      _favorites[stem.id] = stem;
      changed = true;
    }
    for (final pl in _playlists) {
      final idx = pl.stems.indexWhere((s) => s.id == stem.id);
      if (idx != -1) {
        pl.stems[idx] = stem;
        changed = true;
      }
    }
    if (changed) {
      await _savePlaylists();
      await _saveFavorites();
      onVaultChanged?.call();
    }
  }

  /// Upgrades tracks in existing playlists that share the playlist mosaic artwork
  /// to their distinct track posters in the background.
  void upgradePlaylistPostersInBackground() {
    Future.microtask(() async {
      bool anyUpdated = false;

      Future<String?> fetchStudioArt(String title, String artist) async {
        try {
          final cleanT = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceAll('\u00a0', ' ').trim();
          final cleanA = artist.replaceAll('\u00a0', ' ').trim();
          final q = '$cleanT $cleanA'.trim();
          final uri = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(q)}&entity=song&limit=1');
          final res = await http.get(uri).timeout(const Duration(seconds: 2));
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
        return null;
      }

      for (final pl in _playlists) {
        // Collect indices of stems that have mosaic/playlist art or empty art
        final List<int> needsArtIndices = [];
        for (int i = 0; i < pl.stems.length; i++) {
          final s = pl.stems[i];
          if (s.artworkUrl.isEmpty || s.artworkUrl == pl.artworkUrl || s.artworkUrl.contains('mosaic')) {
            needsArtIndices.add(i);
          }
        }

        if (needsArtIndices.isEmpty) continue;

        // Process in concurrent chunks of 5
        for (int chunkStart = 0; chunkStart < needsArtIndices.length; chunkStart += 5) {
          final chunk = needsArtIndices.sublist(
            chunkStart,
            (chunkStart + 5 > needsArtIndices.length) ? needsArtIndices.length : chunkStart + 5,
          );

          await Future.wait(chunk.map((idx) async {
            final stem = pl.stems[idx];
            String? newArt = await fetchStudioArt(stem.title, stem.artistName);

            // Fallback to YouTube thumbnail if stem has a valid YouTube ID
            if (newArt == null && stem.sourceId.length == 11 && !stem.sourceId.contains(' ')) {
              newArt = 'https://i.ytimg.com/vi/${stem.sourceId}/hqdefault.jpg';
            }

            if (newArt != null && newArt.isNotEmpty && newArt != stem.artworkUrl) {
              pl.stems[idx] = pl.stems[idx].copyWith(artworkUrl: newArt);
              anyUpdated = true;
            }
          }));

          // Notify UI incrementally as batches resolve
          if (anyUpdated) {
            await _savePlaylists();
            onVaultChanged?.call();
          }
        }
      }
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _favorites.values.map((s) => s.toJson()).toList();
    await prefs.setString(_favKey, jsonEncode(jsonList));
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _playlists.map((p) => p.toJson()).toList();
    await prefs.setString(_playlistKey, jsonEncode(jsonList));
  }
}
