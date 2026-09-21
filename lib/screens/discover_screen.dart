import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/stem.dart';
import '../providers/player_provider.dart';
import '../providers/vibe_provider.dart';
import '../services/innertube_feed_service.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_row.dart';
import 'playlist_detail_screen.dart';
import 'settings_sheet.dart';
import 'vibe/vibe_home_sheet.dart';
import 'vibe/vibe_room_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
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

  List<Stem> _trendingTracks = _curatedTrending;
  List<Stem> _recentTracks = [];
  bool _isLoadingCharts = false;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  Future<void> _loadFeeds() async {
    setState(() {
      _recentTracks = VaultService().getRecentTracks(limit: 10);
    });

    try {
      final liveCharts = await InnertubeFeedService().fetchCharts();
      if (mounted && liveCharts.isNotEmpty) {
        setState(() {
          _trendingTracks = liveCharts;
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _isLoadingCharts = true);
    await _loadFeeds();
    if (mounted) {
      setState(() => _isLoadingCharts = false);
    }
  }

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
        actions: [
          Consumer<VibeProvider>(
            builder: (context, vibe, _) {
              final isInRoom = vibe.isInRoom;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.sensors_rounded,
                      color: isInRoom ? AppTheme.neon : Colors.white70,
                      size: 22,
                    ),
                    tooltip: isInRoom ? 'Party Active (${vibe.room?.code})' : 'ShreyX Vibe (Party Mode)',
                    onPressed: () {
                      if (isInRoom) {
                        VibeRoomScreen.push(context);
                      } else {
                        VibeHomeSheet.show(context);
                      }
                    },
                  ),
                  if (isInRoom)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.neon,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neon.withValues(alpha: 0.8),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppTheme.neon, size: 22),
            tooltip: 'Audio & App Settings',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const SettingsSheet(),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.neon,
        backgroundColor: AppTheme.bgCard,
        onRefresh: _refresh,
        child: ListView(
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
                        'AUTONOMOUS FLOW',
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
                      'Infinite Hi-Fi Sound',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Dynamic radio, volume normalization, seamless crossfade & offline vault.',
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
                        'Quick Play Flow',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: () {
                        if (_trendingTracks.isNotEmpty) {
                          player.playStem(_trendingTracks.first, queue: _trendingTracks);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Jump Back In / Recently Played Section
            if (_recentTracks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: const [
                    Icon(Icons.history_rounded, color: AppTheme.cyan, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'JUMP BACK IN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _recentTracks.length,
                  itemBuilder: (context, idx) {
                    final stem = _recentTracks[idx];
                    return GestureDetector(
                      onTap: () => player.playWithRadio(stem),
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 1.0,
                                child: stem.artworkUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: stem.artworkUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(color: AppTheme.bgElevated),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppTheme.bgElevated,
                                          child: const Icon(Icons.music_note, color: Colors.white24),
                                        ),
                                      )
                                    : Container(
                                        color: AppTheme.bgElevated,
                                        child: const Icon(Icons.music_note, color: Colors.white24),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              stem.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            ),
                            Text(
                              stem.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Trending Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.trending_up_rounded, color: AppTheme.neon, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _isLoadingCharts ? 'UPDATING CHARTS...' : 'TOP CHARTS & TRENDING',
                        style: const TextStyle(
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
                      if (_trendingTracks.isNotEmpty) {
                        player.playStem(_trendingTracks.first, queue: _trendingTracks);
                      }
                    },
                    label: const Text('Play All', style: TextStyle(color: AppTheme.cyan, fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // Trending Tracks with full playlist queue passed
            ..._trendingTracks.take(15).map((stem) => TrackRow(
                  stem: stem,
                  onTap: () => player.playStem(stem, queue: _trendingTracks),
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
