import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_row.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

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

    final totalSec = playlist.stems.fold<int>(0, (sum, s) => sum + s.durationSec);
    final totalDurationStr = _formatTotalDuration(totalSec);

    return Scaffold(
      body: CustomScrollView(
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
                  if (playlist.artworkUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: playlist.artworkUrl,
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
                          playlist.name,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${playlist.stems.length} tracks${totalDurationStr.isNotEmpty ? ' • $totalDurationStr' : ''}',
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
                icon: playlist.stems.isNotEmpty && playlist.stems.every((s) => vault.isDownloaded(s.id))
                    ? const Icon(Icons.download_done_rounded, color: AppTheme.neon)
                    : vault.isPlaylistDownloading(playlist.id)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.neon,
                            ),
                          )
                        : const Icon(Icons.download_for_offline_outlined, color: AppTheme.neon),
                tooltip: vault.isPlaylistDownloading(playlist.id)
                    ? 'Downloading ${(vault.getPlaylistProgress(playlist.id) * 100).toInt()}%'
                    : 'Download All for Offline',
                onPressed: () {
                  if (vault.isPlaylistDownloading(playlist.id)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading "${playlist.name}" (${(vault.getPlaylistProgress(playlist.id) * 100).toInt()}%)... Check Downloads tab for progress.'),
                        backgroundColor: const Color(0xFF181824),
                      ),
                    );
                    return;
                  }
                  vault.downloadPlaylist(playlist);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Downloading "${playlist.name}" for offline playback...'),
                      backgroundColor: const Color(0xFF181824),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                onPressed: () {
                  vault.deletePlaylist(playlist.id);
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
                        if (playlist.stems.isNotEmpty) {
                          player.playStem(playlist.stems.first, queue: playlist.stems);
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
                        if (playlist.stems.isNotEmpty) {
                          player.shufflePlay(playlist.stems);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Track List
          if (playlist.stems.isEmpty)
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
                  final stem = playlist.stems[idx];
                  return TrackRow(
                    stem: stem,
                    onTap: () => player.playStem(stem, queue: playlist.stems),
                    playlistContextId: playlist.id,
                    playlistContextTitle: playlist.name,
                    playlistContextArtwork: playlist.artworkUrl,
                  );
                },
                childCount: playlist.stems.length,
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 90),
          ),
        ],
      ),
    );
  }
}
