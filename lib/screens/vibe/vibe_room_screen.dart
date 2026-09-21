import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/stem.dart';
import '../../models/vibe_models.dart';
import '../../providers/player_provider.dart';
import '../../providers/vibe_provider.dart';
import '../../theme/app_theme.dart';
import 'vibe_request_sheet.dart';

class VibeRoomScreen extends StatefulWidget {
  const VibeRoomScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VibeRoomScreen()),
    );
  }

  @override
  State<VibeRoomScreen> createState() => _VibeRoomScreenState();
}

class _VibeRoomScreenState extends State<VibeRoomScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _copyRoomCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.neon, width: 0.8),
        ),
        content: Text('Room code $code copied to clipboard!', style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vibe = context.watch<VibeProvider>();
    final player = context.watch<PlayerProvider>();
    final room = vibe.room;

    if (!vibe.isInRoom || room == null) {
      // Room was left or closed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(child: CircularProgressIndicator(color: AppTheme.neon)),
      );
    }

    final isHost = vibe.isHost;
    final currentTrack = isHost ? player.activeStem : room.playbackState.currentTrack;
    final isPlaying = isHost ? player.isPlaying : room.playbackState.isPlaying;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: InkWell(
          onTap: () => _copyRoomCode(context, room.code),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neon.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sensors_rounded, color: AppTheme.neon, size: 16),
                const SizedBox(width: 6),
                Text(
                  room.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, color: AppTheme.textMuted, size: 14),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
            tooltip: 'Leave Party',
            onPressed: () => _showLeaveDialog(context, vibe, isHost),
          ),
        ],
      ),
      body: Column(
        children: [
          // Room Name & Host Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isHost ? AppTheme.neon.withValues(alpha: 0.15) : AppTheme.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHost ? AppTheme.neon.withValues(alpha: 0.5) : AppTheme.cyan.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isHost ? '👑 HOST CONTROLS' : '🎧 LISTENING IN SYNC',
                    style: TextStyle(
                      color: isHost ? AppTheme.neon : AppTheme.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${room.members.length} listening',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Now Playing Hero Card
          _buildNowPlayingHero(context, currentTrack, isPlaying, isHost, player),

          // Host Moderation Carousel (Pending Joins & Song Requests)
          if (isHost && (vibe.pendingJoins.isNotEmpty || vibe.pendingSuggestions.isNotEmpty))
            _buildHostModerationSection(context, vibe),

          // Tab Bar (Queue vs Members)
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderHairline)),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: AppTheme.neon,
              labelColor: AppTheme.neon,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  icon: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Queue (${room.queue.length})'),
                    ],
                  ),
                ),
                Tab(
                  icon: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Members (${room.members.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab View
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildQueueTab(room.queue, isHost, vibe),
                _buildMembersTab(room.members, isHost, vibe),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.neon,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Request Song', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        onPressed: () => VibeRequestSheet.show(context),
      ),
    );
  }

  Widget _buildNowPlayingHero(
    BuildContext context,
    Stem? track,
    bool isPlaying,
    bool isHost,
    PlayerProvider player,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderHairline),
      ),
      child: Row(
        children: [
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: track != null && track.artworkUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.artworkUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _defaultArtwork(),
                  )
                : _defaultArtwork(),
          ),
          const SizedBox(width: 14),

          // Title & Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.title ?? 'No Track Playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track?.artistName ?? 'Host will start the music',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),

                // Equalizer wave indicator
                Row(
                  children: [
                    Icon(
                      isPlaying ? Icons.graphic_eq_rounded : Icons.pause_circle_outline,
                      color: isPlaying ? AppTheme.neon : AppTheme.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPlaying ? 'Synchronized Stream' : 'Paused',
                      style: TextStyle(
                        color: isPlaying ? AppTheme.neon : AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Host Play/Pause quick button
          if (isHost)
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: AppTheme.neon,
                size: 38,
              ),
              onPressed: () => player.togglePlayPause(),
            ),
        ],
      ),
    );
  }

  Widget _buildHostModerationSection(BuildContext context, VibeProvider vibe) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161426),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.purple.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.admin_panel_settings_rounded, color: AppTheme.purple, size: 16),
              SizedBox(width: 6),
              Text(
                'HOST MODERATION',
                style: TextStyle(
                  color: AppTheme.purple,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Pending Joins
          if (vibe.pendingJoins.isNotEmpty) ...[
            const Text('Join Requests:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            ...vibe.pendingJoins.map((req) {
              final memberId = req['member_id'] as String;
              final name = req['user_name'] as String? ?? 'Guest';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_add_rounded, color: Colors.white60, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: AppTheme.neon, size: 22),
                      tooltip: 'Approve',
                      onPressed: () => vibe.approveJoin(memberId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: AppTheme.danger, size: 22),
                      tooltip: 'Decline',
                      onPressed: () => vibe.rejectJoin(memberId),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Song Requests
          if (vibe.pendingSuggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Song Requests:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            ...vibe.pendingSuggestions.map((sugg) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderHairline),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: sugg.stem.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: sugg.stem.artworkUrl,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _defaultArtwork(),
                            )
                          : _defaultArtwork(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sugg.stem.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                          Text(
                            'Requested by ${sugg.suggesterName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    // Action Buttons
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.neon,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Play Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => vibe.approveSuggestion(sugg.id, playNow: true),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.cyan,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('+ Queue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => vibe.approveSuggestion(sugg.id, playNow: false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                      onPressed: () => vibe.rejectSuggestion(sugg.id),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueTab(List<Stem> queue, bool isHost, VibeProvider vibe) {
    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.queue_music_rounded, size: 48, color: Colors.white12),
            SizedBox(height: 8),
            Text('Queue is empty', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            SizedBox(height: 4),
            Text('Members can tap "Request Song" below', style: TextStyle(color: Colors.white30, fontSize: 11)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80, top: 8),
      itemCount: queue.length,
      itemBuilder: (context, idx) {
        final stem = queue[idx];
        return ListTile(
          leading: Text(
            '${idx + 1}',
            style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          title: Text(
            stem.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            stem.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        );
      },
    );
  }

  Widget _buildMembersTab(List<VibeMember> members, bool isHost, VibeProvider vibe) {
    final colors = [
      AppTheme.neon,
      AppTheme.cyan,
      AppTheme.purple,
      Colors.orangeAccent,
      Colors.pinkAccent,
      Colors.tealAccent,
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80, top: 8),
      itemCount: members.length,
      itemBuilder: (context, idx) {
        final m = members[idx];
        final color = colors[m.colorIndex % colors.length];

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            m.name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          trailing: m.isHost
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.neon.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.neon.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'HOST',
                    style: TextStyle(color: AppTheme.neon, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                )
              : isHost
                  ? PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18),
                      onSelected: (val) {
                        if (val == 'transfer') {
                          vibe.transferHost(m.id);
                        } else if (val == 'kick') {
                          vibe.kickMember(m.id);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'transfer',
                          child: Text('Make Room Host'),
                        ),
                        const PopupMenuItem(
                          value: 'kick',
                          child: Text('Remove Member', style: TextStyle(color: AppTheme.danger)),
                        ),
                      ],
                    )
                  : null,
        );
      },
    );
  }

  Widget _defaultArtwork() {
    return Container(
      width: 64,
      height: 64,
      color: AppTheme.bgElevated,
      child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 30),
    );
  }

  void _showLeaveDialog(BuildContext context, VibeProvider vibe, bool isHost) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isHost ? 'Leave & Close Party?' : 'Leave Party?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          isHost
              ? 'Leaving will transfer host to another member or close the room.'
              : 'You will stop listening synchronously with the party.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.of(ctx).pop();
              vibe.leaveRoom();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
