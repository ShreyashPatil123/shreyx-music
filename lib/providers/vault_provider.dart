import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/stem.dart';
import '../services/download_service.dart';
import '../services/vault_service.dart';

class VaultProvider extends ChangeNotifier {
  final VaultService _vaultService = VaultService();
  final DownloadService _downloadService = DownloadService();

  StreamSubscription? _downloadProgressSub;

  List<Stem> get favorites => _vaultService.favorites;
  List<Playlist> get playlists => _vaultService.playlists;
  List<Stem> get allDownloads => _downloadService.getAllDownloads();

  VaultProvider() {
    _init();
  }

  Future<void> _init() async {
    _vaultService.onVaultChanged = () {
      notifyListeners();
    };
    await _vaultService.init();
    await _downloadService.init();
    _downloadProgressSub = _downloadService.progressStream.listen((_) {
      notifyListeners();
    });
    notifyListeners();
  }

  bool isFavorite(String stemId) => _vaultService.isFavorite(stemId);

  Future<void> toggleFavorite(Stem stem) async {
    await _vaultService.toggleFavorite(stem);
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String name, {String description = '', List<Stem>? stems}) async {
    final pl = await _vaultService.createPlaylist(name, description: description, stems: stems);
    notifyListeners();
    return pl;
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _vaultService.deletePlaylist(playlistId);
    notifyListeners();
  }

  Future<void> addStemToPlaylist(String playlistId, Stem stem) async {
    await _vaultService.addStemToPlaylist(playlistId, stem);
    notifyListeners();
  }

  Future<void> removeStemFromPlaylist(String playlistId, String stemId) async {
    await _vaultService.removeStemFromPlaylist(playlistId, stemId);
    notifyListeners();
  }

  bool isDownloaded(String stemId) => _downloadService.isDownloaded(stemId);
  bool isDownloading(String stemId) => _downloadService.isDownloading(stemId);
  bool isPlaylistDownloading(String playlistId) =>
      _downloadService.isPlaylistDownloading(playlistId);
  double getDownloadProgress(String stemId) => _downloadService.getProgress(stemId);
  double getPlaylistProgress(String playlistId) =>
      _downloadService.getPlaylistProgress(playlistId);

  List<ActiveDownload> get activeDownloads => _downloadService.activeDownloads;
  List<ActivePlaylistDownload> get activePlaylists => _downloadService.activePlaylists;

  Future<void> downloadStem(
    Stem stem, {
    String? playlistId,
    String? playlistTitle,
    String? playlistArtwork,
  }) async {
    await _downloadService.downloadStem(
      stem,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
      playlistArtwork: playlistArtwork,
    );
    notifyListeners();
  }

  Future<void> downloadPlaylist(Playlist playlist) async {
    await _downloadService.downloadPlaylist(playlist);
    notifyListeners();
  }

  void cancelDownload(String stemId) {
    _downloadService.cancelDownload(stemId);
    notifyListeners();
  }

  void cancelPlaylistDownload(String playlistId) {
    _downloadService.cancelPlaylistDownload(playlistId);
    notifyListeners();
  }

  Future<void> removeDownload(String stemId) async {
    await _downloadService.removeDownload(stemId);
    notifyListeners();
  }

  List<DownloadedPlaylistGroup> getGroupedDownloads() =>
      _downloadService.getGroupedDownloads();

  @override
  void dispose() {
    _downloadProgressSub?.cancel();
    super.dispose();
  }
}
