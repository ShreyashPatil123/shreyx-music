import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/stem.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_row.dart';
import 'playlist_detail_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  static final List<Stem> _curatedTrending = [
    Stem(
      id: 'yt_trending_1',
      title: 'Starboy',
      artistName: 'The Weeknd ft. Daft Punk',
      artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&q=80',
      durationSec: 230,
      sourceId: '34Na4j8AVgA',
    ),
    Stem(
      id: 'yt_trending_2',
      title: 'Blinding Lights',
      artistName: 'The Weeknd',
      artworkUrl: 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=500&q=80',
      durationSec: 200,
      sourceId: '4NRXx6U8ABQ',
    ),
    Stem(
      id: 'yt_trending_3',
      title: 'Midnight City',
      artistName: 'M83',
      artworkUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=500&q=80',
      durationSec: 243,
      sourceId: 'dX3k_QDnzHE',
    ),
    Stem(
      id: 'yt_trending_4',
      title: 'After Hours',
      artistName: 'The Weeknd',
      artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80',
      durationSec: 361,
      sourceId: 'ygTZZpVkm3o',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.bolt_rounded, color: AppTheme.neon, size: 24),
            SizedBox(width: 8),
            Text(
              'SHREYX MUSIC',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // Hero Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1E2E), Color(0xFF0F0F16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: AppTheme.borderHairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.neon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'FEATURED HERO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppTheme.neon,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Autonomous Audio Flow',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'High-fidelity lossless streams with native background playback & offline vault.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      'Quick Play Mix',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: () {
                      player.playStem(_curatedTrending.first, queue: _curatedTrending);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Trending Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.trending_up_rounded, color: AppTheme.neon, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'TRENDING STREAMS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 16, color: AppTheme.cyan),
                  onPressed: () {
                    player.playStem(_curatedTrending.first, queue: _curatedTrending);
                  },
                  label: const Text('Play All', style: TextStyle(color: AppTheme.cyan, fontSize: 12.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Trending Tracks with full playlist queue passed
          ..._curatedTrending.map((stem) => TrackRow(
                stem: stem,
                onTap: () => player.playStem(stem, queue: _curatedTrending),
              )),

          // Curated Playlists
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              'CURATED PLAYLISTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.textMuted,
              ),
            ),
          ),

          SizedBox(
            height: 195,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildCuratedCard(
                  context,
                  title: 'Cyberpunk Synthwave',
                  trackCount: 4,
                  artworkUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=500&q=80',
                  stems: _curatedTrending,
                ),
                _buildCuratedCard(
                  context,
                  title: 'Late Night Chill',
                  trackCount: 3,
                  artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&q=80',
                  stems: _curatedTrending.take(3).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratedCard(
    BuildContext context, {
    required String title,
    required int trackCount,
    required String artworkUrl,
    required List<Stem> stems,
  }) {
    return GestureDetector(
      onTap: () {
        final pl = Playlist(
          id: 'curated_${title.hashCode}',
          name: title,
          artworkUrl: artworkUrl,
          stems: stems,
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: pl)),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14.0),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: CachedNetworkImage(
                  imageUrl: artworkUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppTheme.bgElevated),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
            ),
            Text(
              '$trackCount tracks',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
