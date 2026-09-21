import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../theme/app_theme.dart';

class TrackRow extends StatelessWidget {
  final Stem stem;
  final VoidCallback? onTap;
  final String? playlistContextId;
  final String? playlistContextTitle;
  final String? playlistContextArtwork;

  const TrackRow({
    super.key,
    required this.stem,
    this.onTap,
    this.playlistContextId,
    this.playlistContextTitle,
    this.playlistContextArtwork,
  });

  String _formatDuration(int sec) {
    if (sec <= 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s < 10 ? '0' : ''}$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final vault = context.watch<VaultProvider>();

    final isCurrent = player.activeStem?.id == stem.id;
    final isDownloaded = vault.isDownloaded(stem.id);
    final isDownloading = vault.isDownloading(stem.id);
    final downloadProgress = vault.getDownloadProgress(stem.id);

    return InkWell(
      onTap: onTap ?? () => player.playStem(stem),
      splashColor: AppTheme.neon.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Artwork thumbnail
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: isCurrent ? AppTheme.neon.withValues(alpha: 0.5) : AppTheme.borderHairline,
                  width: isCurrent ? 1.5 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      color: AppTheme.bgElevated,
                      child: stem.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: stem.artworkUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: AppTheme.bgElevated),
                              errorWidget: (context, url, error) => const Icon(Icons.music_note, color: AppTheme.textSecondary),
                            )
                          : const Icon(Icons.music_note, color: AppTheme.textSecondary),
                    ),
                    if (isCurrent && player.isBuffering)
                      Container(
                        width: 48,
                        height: 48,
                        color: Colors.black54,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.neon),
                            ),
                          ),
                        ),
                      )
                    else if (isCurrent && player.isPlaying)
                      Container(
                        width: 48,
                        height: 48,
                        color: Colors.black45,
                        child: const Center(
                          child: Icon(Icons.equalizer_rounded, color: AppTheme.neon, size: 24),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Track details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stem.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppTheme.neon : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isDownloaded) ...[
                        const Icon(Icons.check_circle, size: 13, color: AppTheme.neon),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          stem.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (stem.durationSec > 0)
                        Text(
                          _formatDuration(stem.durationSec),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 1-Tap Download Button
            IconButton(
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              icon: isDownloaded
                  ? const Icon(Icons.download_done_rounded, color: AppTheme.neon)
                  : isDownloading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: downloadProgress > 0 ? downloadProgress : null,
                            color: AppTheme.cyan,
                          ),
                        )
                      : const Icon(Icons.download_outlined, color: AppTheme.textSecondary),
              onPressed: () {
                if (isDownloaded) {
                  vault.removeDownload(stem.id);
                } else if (!isDownloading) {
                  vault.downloadStem(
                    stem,
                    playlistId: playlistContextId,
                    playlistTitle: playlistContextTitle,
                    playlistArtwork: playlistContextArtwork,
                  );
                }
              },
            ),

            // 3-dots context menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textSecondary),
              color: AppTheme.bgElevated,
              padding: EdgeInsets.zero,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'play_next',
                  child: Row(
                    children: const [
                      Icon(Icons.playlist_play, size: 18, color: AppTheme.cyan),
                      SizedBox(width: 10),
                      Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'add_queue',
                  child: Row(
                    children: const [
                      Icon(Icons.queue_music, size: 18, color: AppTheme.neon),
                      SizedBox(width: 10),
                      Text('Add to Queue', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'fav',
                  child: Row(
                    children: [
                      Icon(
                        vault.isFavorite(stem.id) ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: vault.isFavorite(stem.id) ? AppTheme.neon : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        vault.isFavorite(stem.id) ? 'Remove Favorite' : 'Add to Favorites',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (val) {
                if (val == 'play_next') {
                  player.playNext(stem);
                } else if (val == 'add_queue') {
                  player.addToQueue(stem);
                } else if (val == 'fav') {
                  vault.toggleFavorite(stem);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
