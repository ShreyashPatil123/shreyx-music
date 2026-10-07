import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../services/playlist_pagination_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_row.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Playlist _playlist;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 350) {
      if (!_isLoadingMore && _playlist.hasMore && _errorMessage == null) {
        _loadNextPage();
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_playlist.hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _errorMessage = null;
    });

    try {
      final newStems = await PlaylistPaginationService().loadNextPage(_playlist);
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });

        // Persist updated tracklist to Vault
        context.read<VaultProvider>().updatePlaylist(_playlist);

        // If the player is currently playing this playlist, dynamically append new tracks to queue
        final player = context.read<PlayerProvider>();
        if (player.activeStem?.playlistId == _playlist.id && newStems.isNotEmpty) {
          player.appendTracksToQueue(newStems);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _errorMessage = 'Failed to load more songs: $e';
        });
      }
    }
  }

  String _formatTotalDuration(int totalSec) {
    if (totalSec <= 0) return '';
    final hrs = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    if (hrs > 0) return '$hrs hr $mins min';
    return '$mins min';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final vault = context.watch<VaultProvider>();

    final totalSec = _playlist.stems.fold<int>(0, (sum, s) => sum + s.durationSec);
    final totalDurationStr = _formatTotalDuration(totalSec);
    final countText = _playlist.totalTrackCount != null && _playlist.totalTrackCount! > _playlist.stems.length
        ? '${_playlist.stems.length} of ${_playlist.totalTrackCount} tracks'
        : '${_playlist.stems.length} tracks';

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Collapsible Header
              SliverAppBar(
                expandedHeight: 280.0,
                pinned: true,
                backgroundColor: AppTheme.bg,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_playlist.artworkUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: _playlist.artworkUrl,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: AppTheme.bgElevated),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, AppTheme.bg],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _playlist.name,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$countText${totalDurationStr.isNotEmpty ? ' • $totalDurationStr' : ''}',
                              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: _playlist.stems.isNotEmpty && _playlist.stems.every((s) => vault.isDownloaded(s.id))
                        ? const Icon(Icons.download_done_rounded, color: AppTheme.neon)
                        : vault.isPlaylistDownloading(_playlist.id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.neon,
                                ),
                              )
                            : const Icon(Icons.download_for_offline_outlined, color: AppTheme.neon),
                    tooltip: vault.isPlaylistDownloading(_playlist.id)
                        ? 'Downloading ${(vault.getPlaylistProgress(_playlist.id) * 100).toInt()}%'
                        : 'Download All for Offline',
                    onPressed: () {
                      if (vault.isPlaylistDownloading(_playlist.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading "${_playlist.name}" (${(vault.getPlaylistProgress(_playlist.id) * 100).toInt()}%)... Check Downloads tab for progress.'),
                            backgroundColor: const Color(0xFF181824),
                          ),
                        );
                        return;
                      }
                      vault.downloadPlaylist(_playlist);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Downloading "${_playlist.name}" for offline playback...'),
                          backgroundColor: const Color(0xFF181824),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                    onPressed: () {
                      vault.deletePlaylist(_playlist.id);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),

              // Action Buttons: Play All & Shuffle Play
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.neon,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            if (_playlist.stems.isNotEmpty) {
                              player.playStem(_playlist.stems.first, queue: _playlist.stems, playlistContext: _playlist);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.cyan),
                          label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            if (_playlist.stems.isNotEmpty) {
                              player.shufflePlay(_playlist.stems, playlistContext: _playlist);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Track List
              if (_playlist.stems.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('This playlist is empty.', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final stem = _playlist.stems[idx];
                      return TrackRow(
                        stem: stem,
                        onTap: () => player.playStem(stem, queue: _playlist.stems, playlistContext: _playlist),
                        playlistContextId: _playlist.id,
                        playlistContextTitle: _playlist.name,
                        playlistContextArtwork: _playlist.artworkUrl,
                      );
                    },
                    childCount: _playlist.stems.length,
                  ),
                ),

              // Pagination Loading Spinner
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.neon,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Loading more tracks...',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _loadNextPage,
                            icon: const Icon(Icons.refresh, color: AppTheme.neon, size: 16),
                            label: const Text('Retry', style: TextStyle(color: AppTheme.neon, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (!_playlist.hasMore && _playlist.stems.length >= 50)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(
                      child: Text(
                        'All ${_playlist.stems.length} tracks loaded',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 110),
              ),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: MiniPlayer(),
            ),
          ),
        ],
      ),
    );
  }
}
