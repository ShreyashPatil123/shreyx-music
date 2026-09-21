import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../screens/deck_sheet.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final vault = context.watch<VaultProvider>();
    final stem = player.activeStem;

    if (stem == null) return const SizedBox.shrink();

    final positionMs = player.position.inMilliseconds.toDouble();
    final durationMs = player.duration.inMilliseconds.toDouble();
    final progress = durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
    final isFav = vault.isFavorite(stem.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -200) {
              // Swiped Left -> Skip Next
              player.skipNext();
            } else if (details.primaryVelocity! > 200) {
              // Swiped Right -> Skip Previous
              player.skipPrev();
            }
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const DeckSheet(),
                  );
                },
                borderRadius: BorderRadius.circular(18.0),
                child: Container(
                  height: 66,
                  decoration: BoxDecoration(
                    color: const Color(0xE612131D),
                    borderRadius: BorderRadius.circular(18.0),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Smooth Progress Line with Neon Glow
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.neon),
                      ),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            children: [
                              // Artwork thumbnail with subtle border
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10.0),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  color: AppTheme.bgElevated,
                                  child: stem.artworkUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: stem.artworkUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => Container(color: AppTheme.bgElevated),
                                          errorWidget: (context, url, error) =>
                                              const Icon(Icons.music_note, color: Colors.white54),
                                        )
                                      : const Icon(Icons.music_note, color: Colors.white54),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title, Artist, and Live Playing Equalizer
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (player.isPlaying) ...[
                                          const Icon(Icons.equalizer_rounded, size: 14, color: AppTheme.neon),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            stem.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      stem.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Favorite Button
                              IconButton(
                                iconSize: 22,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: isFav ? AppTheme.danger : AppTheme.textMuted,
                                ),
                                onPressed: () => vault.toggleFavorite(stem),
                              ),

                              const SizedBox(width: 6),

                              // Play / Pause Button with Glow
                              GestureDetector(
                                onTap: () => player.togglePlayPause(),
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.neon,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x6600F5D4),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: player.isBuffering
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: Colors.black,
                                            ),
                                          )
                                        : Icon(
                                            player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            size: 24,
                                            color: Colors.black,
                                          ),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 4),

                              // Skip Next Button (Forward Button)
                              IconButton(
                                iconSize: 28,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                onPressed: () => player.skipNext(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
