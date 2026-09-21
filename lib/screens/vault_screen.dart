import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/link_import_sheet.dart';
import '../widgets/track_row.dart';
import 'playlist_detail_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String? _selectedDownloadGroupId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();

    return PopScope(
      canPop: _selectedDownloadGroupId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedDownloadGroupId != null) {
          setState(() => _selectedDownloadGroupId = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('The Vault'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link_rounded, color: AppTheme.neon),
              tooltip: 'Import Playlist / Song Link',
              onPressed: () => LinkImportSheet.show(context),
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppTheme.neon,
            labelColor: AppTheme.neon,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Favorites (${vault.favorites.length})'),
              Tab(text: 'Playlists (${vault.playlists.length})'),
              Tab(text: 'Downloads (${vault.allDownloads.length})'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildFavoritesTab(vault),
            _buildPlaylistsTab(vault),
            _buildDownloadsTab(vault),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesTab(VaultProvider vault) {
    if (vault.favorites.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.favorite_border_rounded,
        title: 'No Favorites Yet',
        subtitle: 'Tap the heart icon on any song to save it here.',
      );
    }

    final player = context.read<PlayerProvider>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.neon,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    player.playStem(vault.favorites.first, queue: vault.favorites);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.cyan),
                  label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    player.shufflePlay(vault.favorites);
                  },
                ),
              ),
            ],
          ),
        ),
        ...vault.favorites.map((stem) => TrackRow(
              stem: stem,
              onTap: () => player.playStem(stem, queue: vault.favorites),
            )),
      ],
    );
  }

  Widget _buildPlaylistsTab(VaultProvider vault) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: FloatingActionButton.extended(
          backgroundColor: AppTheme.neon,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => _showCreatePlaylistDialog(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          // Link Import Banner at the top of playlists
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.neon.withValues(alpha: 0.16),
                  AppTheme.cyan.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.neon.withValues(alpha: 0.35)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.neon.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: AppTheme.neon, size: 22),
              ),
              title: const Text(
                'Import Playlist from Link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Colors.white),
              ),
              subtitle: const Text(
                'Paste Spotify or YouTube playlist links',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.neon,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Import',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.black),
                ),
              ),
              onTap: () => LinkImportSheet.show(context),
            ),
          ),

          if (vault.playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40.0),
              child: _buildEmptyTab(
                icon: Icons.playlist_add_rounded,
                title: 'No Custom Playlists',
                subtitle: 'Import a playlist from Spotify/YouTube above or tap "New Playlist" below.',
              ),
            )
          else ...[
            const Text(
              'YOUR PLAYLISTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ...vault.playlists.map((pl) => _buildPlaylistCard(pl)),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaylistCard(Playlist pl) {
    return Card(
      color: const Color(0xFF13131D),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.0),
        side: const BorderSide(color: AppTheme.borderHairline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            width: 52,
            height: 52,
            color: AppTheme.bgElevated,
            child: pl.artworkUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: pl.artworkUrl, fit: BoxFit.cover)
                : const Icon(Icons.queue_music, color: AppTheme.neon),
          ),
        ),
        title: Text(
          pl.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Colors.white),
        ),
        subtitle: Text(
          '${pl.stems.length} tracks',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: pl)),
          );
        },
      ),
    );
  }

  // ==========================================
  // GROUPED OFFLINE DOWNLOADS TAB
  // (Playlist Groups & Standalone Tracks)
  // ==========================================
  Widget _buildDownloadsTab(VaultProvider vault) {
    final groups = vault.getGroupedDownloads();
    final activePlaylists = vault.activePlaylists;
    final activeDownloads = vault.activeDownloads;
    final hasActive = activePlaylists.isNotEmpty || activeDownloads.isNotEmpty;

    if (groups.isEmpty && !hasActive) {
      return _buildEmptyTab(
        icon: Icons.download_done_rounded,
        title: 'No Offline Downloads',
        subtitle: 'Tap the download icon on any song or playlist for 100% offline playback.',
      );
    }

    // Drill-Down View for a specific downloaded playlist
    if (_selectedDownloadGroupId != null) {
      final selectedGroup = groups.firstWhere(
        (g) => g.id == _selectedDownloadGroupId,
        orElse: () => groups.first,
      );

      return Column(
        children: [
          // Back button header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF101018),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.neon),
                  onPressed: () => setState(() => _selectedDownloadGroupId = null),
                ),
                Expanded(
                  child: Text(
                    selectedGroup.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ),
                Text(
                  '${selectedGroup.sizeInMB.toStringAsFixed(1)} MB',
                  style: const TextStyle(color: AppTheme.cyan, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Action Bar for downloaded playlist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      if (selectedGroup.stems.isNotEmpty) {
                        context.read<PlayerProvider>().playStem(selectedGroup.stems.first, queue: selectedGroup.stems);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.cyan),
                    label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      if (selectedGroup.stems.isNotEmpty) {
                        context.read<PlayerProvider>().shufflePlay(selectedGroup.stems);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Track list in this downloaded playlist
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: selectedGroup.stems.length,
              itemBuilder: (context, idx) {
                final stem = selectedGroup.stems[idx];
                return TrackRow(
                  stem: stem,
                  onTap: () => context.read<PlayerProvider>().playStem(stem, queue: selectedGroup.stems),
                  playlistContextId: selectedGroup.id,
                  playlistContextTitle: selectedGroup.title,
                );
              },
            ),
          ),
        ],
      );
    }

    // Overview View: Summary + Downloaded Playlist Cards
    final totalSizeMB = groups.fold<double>(0.0, (sum, g) => sum + g.sizeInMB);
    final totalTracks = groups.fold<int>(0, (sum, g) => sum + g.stems.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        // ── Active Downloads Section (Live Progress Bars) ──
        if (hasActive) _buildActiveDownloadsSection(vault),

        // Storage Summary Banner
        if (groups.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF12121A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderHairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OFFLINE STORAGE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalTracks Songs Downloaded',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${totalSizeMB.toStringAsFixed(1)} MB Used',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cyan),
                  ),
                ),
              ],
            ),
          ),

        if (groups.isNotEmpty) ...[
          const Text(
            'DOWNLOADED PLAYLISTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          // Group Cards
          ...groups.map((g) => _buildGroupCard(g)),
        ],
      ],
    );
  }

  Widget _buildActiveDownloadsSection(VaultProvider vault) {
    final activePlaylists = vault.activePlaylists;
    final activeDownloads = vault.activeDownloads;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.neon,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'DOWNLOADING NOW (${activePlaylists.length + activeDownloads.length})',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.neon,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Active Playlist Downloads
        ...activePlaylists.map((p) => _buildActivePlaylistCard(vault, p)),

        // Active Track Downloads
        ...activeDownloads.map((d) => _buildActiveSongCard(vault, d)),

        const SizedBox(height: 16),
        const Divider(color: AppTheme.borderHairline),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildActivePlaylistCard(VaultProvider vault, ActivePlaylistDownload p) {
    final progress = vault.getPlaylistProgress(p.playlistId);
    final percent = (progress * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.neon.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: p.artworkUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: p.artworkUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.white10,
                            child: const Icon(Icons.playlist_play_rounded, color: AppTheme.neon),
                          ),
                        )
                      : Container(
                          color: Colors.white10,
                          child: const Icon(Icons.playlist_play_rounded, color: AppTheme.neon),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.currentSongTitle.isNotEmpty
                          ? 'Track ${p.completedCount + 1} of ${p.totalCount}: ${p.currentSongTitle}'
                          : 'Preparing download...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.neon),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                onPressed: () => vault.cancelPlaylistDownload(p.playlistId),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.neon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSongCard(VaultProvider vault, ActiveDownload d) {
    final progress = d.progress;
    final percent = (progress * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF13131D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: d.stem.artworkUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: d.stem.artworkUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.white10,
                            child: const Icon(Icons.music_note_rounded, color: AppTheme.cyan),
                          ),
                        )
                      : Container(
                          color: Colors.white10,
                          child: const Icon(Icons.music_note_rounded, color: AppTheme.cyan),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.stem.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.status == 'resolving'
                          ? 'Resolving audio stream...'
                          : '${d.stem.artistName} • Downloading',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$percent%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cyan),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: () => vault.cancelDownload(d.stem.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyan),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(DownloadedPlaylistGroup g) {
    final player = context.read<PlayerProvider>();

    return Card(
      color: const Color(0xFF13131D),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.0),
        side: const BorderSide(color: AppTheme.borderHairline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: 52,
            height: 52,
            child: g.artworkUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: g.artworkUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.white10),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.white10,
                      child: const Icon(Icons.album_rounded, color: AppTheme.cyan),
                    ),
                  )
                : Container(
                    color: Colors.white10,
                    child: const Icon(Icons.album_rounded, color: AppTheme.cyan),
                  ),
          ),
        ),
        title: Text(
          g.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            '${g.stems.length} songs • ${g.sizeInMB.toStringAsFixed(1)} MB',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, size: 20, color: AppTheme.neon),
              onPressed: () {
                if (g.stems.isNotEmpty) {
                  player.shufflePlay(g.stems);
                }
              },
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
        onTap: () {
          setState(() {
            _selectedDownloadGroupId = g.id;
          });
        },
      ),
    );
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.white12),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0)),
        title: const Text('Create New Playlist', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: AppTheme.textMuted),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.neon)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neon,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
            onPressed: () {
              final text = nameCtrl.text.trim();
              if (text.isNotEmpty) {
                context.read<VaultProvider>().createPlaylist(text);
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}
