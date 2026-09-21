import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../providers/vibe_provider.dart';
import '../services/audio_normalization_service.dart';
import '../services/equalizer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_scrubber_bar.dart';
import 'settings_sheet.dart';
import 'vibe/vibe_home_sheet.dart';
import 'vibe/vibe_room_screen.dart';

class DeckSheet extends StatefulWidget {
  const DeckSheet({super.key});

  @override
  State<DeckSheet> createState() => _DeckSheetState();
}

enum _DeckViewMode { art, lyrics, queue }

class _DeckSheetState extends State<DeckSheet> {
  _DeckViewMode _viewMode = _DeckViewMode.art;
  final ScrollController _lyricsScrollCtrl = ScrollController();
  final ScrollController _queueScrollCtrl = ScrollController();

  @override
  void dispose() {
    _lyricsScrollCtrl.dispose();
    _queueScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final vault = context.watch<VaultProvider>();
    final vibe = context.watch<VibeProvider>();
    final canControl = vibe.canControlPlayback;
    final stem = player.activeStem;

    void notifyHostControls() {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppTheme.cyan, width: 0.8),
          ),
          content: const Text(
            'Host controls playback in ShreyX Vibe. Use "Request Song" to suggest!',
            style: TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (stem == null) {
      return Container(
        height: 220,
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: const Center(
          child: Text('No song playing', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    final isFav = vault.isFavorite(stem.id);
    final isDownloaded = vault.isDownloaded(stem.id);
    final isDownloading = vault.isDownloading(stem.id);

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: AppTheme.borderHairline),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 40,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar: Drag indicator & Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.bgElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderHairline),
                        ),
                        child: const Text(
                          'PLAYING FROM DECK',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.neon,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          stem.albumName ?? 'ShreyX Music',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer<VibeProvider>(
                        builder: (context, vibe, _) {
                          final isInRoom = vibe.isInRoom;
                          return IconButton(
                            icon: Icon(
                              Icons.sensors_rounded,
                              color: isInRoom ? AppTheme.neon : Colors.white70,
                              size: 22,
                            ),
                            tooltip: isInRoom ? 'Party Active (${vibe.room?.code})' : 'Listen Together (Vibe)',
                            onPressed: () {
                              if (isInRoom) {
                                VibeRoomScreen.push(context);
                              } else {
                                VibeHomeSheet.show(context);
                              }
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 22),
                        tooltip: 'Settings & EQ',
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const SettingsSheet(),
                          ).then((_) => setState(() {}));
                        },
                      ),
                      IconButton(
                        icon: isDownloaded
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.neon, size: 24)
                            : isDownloading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyan),
                                  )
                                : const Icon(Icons.download_outlined, color: Colors.white70, size: 24),
                        onPressed: () {
                          if (isDownloaded) {
                            vault.removeDownload(stem.id);
                          } else if (!isDownloading) {
                            vault.downloadStem(stem);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main View Switcher Body: Art vs Lyrics vs Queue
            Expanded(
              child: _buildCurrentView(player, stem),
            ),

            // Track Details: Title, Artist, and Favorite
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 6.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stem.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    icon: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? AppTheme.danger : AppTheme.textSecondary,
                    ),
                    onPressed: () => vault.toggleFavorite(stem),
                  ),
                ],
              ),
            ),

            // Song Scrubber Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SongScrubberBar(
                enabled: canControl,
                position: player.position,
                duration: player.duration.inSeconds > 0
                    ? player.duration
                    : Duration(seconds: stem.durationSec),
                onSeek: (target) {
                  if (canControl) {
                    player.seek(target);
                  } else {
                    notifyHostControls();
                  }
                },
              ),
            ),

            // Studio Spec Pills
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderHairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.graphic_eq_rounded, size: 12, color: AppTheme.neon),
                          SizedBox(width: 5),
                          Text(
                            'HQ OPUS • 160 KBPS',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const SettingsSheet(),
                        ).then((_) => setState(() {}));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AudioNormalizationService().isEnabled
                              ? AppTheme.neon.withValues(alpha: 0.12)
                              : AppTheme.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AudioNormalizationService().isEnabled
                                ? AppTheme.neon.withValues(alpha: 0.4)
                                : AppTheme.borderHairline,
                          ),
                        ),
                        child: Text(
                          AudioNormalizationService().isEnabled ? 'NORM: -14 LUFS' : 'NORM: OFF',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AudioNormalizationService().isEnabled ? AppTheme.neon : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const SettingsSheet(),
                        ).then((_) => setState(() {}));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderHairline),
                        ),
                        child: Text(
                          'EQ: ${EqualizerService().activePreset.name.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppTheme.cyan,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Vibe Member Status Pill
            if (!canControl)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sensors_rounded, size: 14, color: AppTheme.cyan),
                      const SizedBox(width: 6),
                      Text(
                        'Synced to Party (${vibe.room?.code}) • Host Controls Playback',
                        style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

            // Playback Controls Hub
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Shuffle
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 22,
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: canControl
                          ? (player.isShuffled ? AppTheme.neon : AppTheme.textMuted)
                          : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                    onPressed: canControl ? () => player.toggleShuffle() : notifyHostControls,
                  ),

                  // Seek backward -10s
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 24,
                    icon: Icon(
                      Icons.replay_10_rounded,
                      color: canControl ? AppTheme.textSecondary : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                    onPressed: canControl ? () => player.seekBy(-10) : notifyHostControls,
                  ),

                  // Skip Previous
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 34,
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      color: canControl ? Colors.white : Colors.white24,
                    ),
                    onPressed: canControl ? () => player.skipPrev() : notifyHostControls,
                  ),

                  // Primary Play / Pause Button with Glow
                  GestureDetector(
                    onTap: canControl ? () => player.togglePlayPause() : notifyHostControls,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: canControl ? AppTheme.primaryGradient : null,
                        color: canControl ? null : AppTheme.bgElevated,
                        shape: BoxShape.circle,
                        border: canControl ? null : Border.all(color: AppTheme.cyan.withValues(alpha: 0.4)),
                        boxShadow: canControl
                            ? const [
                                BoxShadow(
                                  color: Color(0x7700F5D4),
                                  blurRadius: 20,
                                  offset: Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: player.isBuffering
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 36,
                                color: canControl ? Colors.black : AppTheme.cyan,
                              ),
                      ),
                    ),
                  ),

                  // Skip Next (Forward Button)
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 34,
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: canControl ? Colors.white : Colors.white24,
                    ),
                    onPressed: canControl ? () => player.skipNext() : notifyHostControls,
                  ),

                  // Seek forward +10s
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 24,
                    icon: Icon(
                      Icons.forward_10_rounded,
                      color: canControl ? AppTheme.textSecondary : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                    onPressed: canControl ? () => player.seekBy(10) : notifyHostControls,
                  ),

                  // Loop Mode
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    iconSize: 22,
                    icon: Icon(
                      player.loopMode == LoopMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: canControl
                          ? (player.loopMode != LoopMode.off ? AppTheme.cyan : AppTheme.textMuted)
                          : AppTheme.textMuted.withValues(alpha: 0.4),
                    ),
                    onPressed: canControl ? () => player.cycleLoopMode() : notifyHostControls,
                  ),
                ],
              ),
            ),

            // Mode Switcher: Master Art vs Lyrics vs Up Next Queue
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Cover Art'),
                    selected: _viewMode == _DeckViewMode.art,
                    selectedColor: AppTheme.bgElevated,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: _viewMode == _DeckViewMode.art ? AppTheme.neon : AppTheme.borderHairline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _viewMode == _DeckViewMode.art ? AppTheme.neon : AppTheme.textSecondary,
                    ),
                    onSelected: (_) => setState(() => _viewMode = _DeckViewMode.art),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.lyrics_outlined, size: 15),
                    label: const Text('Lyrics'),
                    selected: _viewMode == _DeckViewMode.lyrics,
                    selectedColor: AppTheme.bgElevated,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: _viewMode == _DeckViewMode.lyrics ? AppTheme.cyan : AppTheme.borderHairline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _viewMode == _DeckViewMode.lyrics ? AppTheme.cyan : AppTheme.textSecondary,
                    ),
                    onSelected: (_) => setState(() => _viewMode = _DeckViewMode.lyrics),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.queue_music_rounded, size: 15),
                    label: Text('Queue (${player.queue.length})'),
                    selected: _viewMode == _DeckViewMode.queue,
                    selectedColor: AppTheme.bgElevated,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: _viewMode == _DeckViewMode.queue ? AppTheme.purple : AppTheme.borderHairline,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _viewMode == _DeckViewMode.queue ? AppTheme.purple : AppTheme.textSecondary,
                    ),
                    onSelected: (_) => setState(() => _viewMode = _DeckViewMode.queue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(PlayerProvider player, Stem stem) {
    switch (_viewMode) {
      case _DeckViewMode.art:
        return _buildArtworkView(stem, player.isPlaying);
      case _DeckViewMode.lyrics:
        return _buildLyricsView(player);
      case _DeckViewMode.queue:
        return _buildQueueView(player);
    }
  }

  Widget _buildArtworkView(Stem stem, bool isPlaying) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 12.0),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28.0),
              boxShadow: [
                BoxShadow(
                  color: isPlaying ? const Color(0x3300F5D4) : Colors.black54,
                  blurRadius: 36,
                  spreadRadius: 2,
                  offset: const Offset(0, 12),
                ),
                const BoxShadow(
                  color: Colors.black87,
                  blurRadius: 24,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28.0),
              child: stem.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: stem.artworkUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.bgElevated),
                      errorWidget: (context, url, error) => Container(
                        color: AppTheme.bgElevated,
                        child: const Icon(Icons.album_rounded, size: 80, color: Colors.white24),
                      ),
                    )
                  : Container(
                      color: AppTheme.bgElevated,
                      child: const Icon(Icons.album_rounded, size: 80, color: Colors.white24),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView(PlayerProvider player) {
    if (player.isLoadingLyrics) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.cyan),
      );
    }

    final lyrics = player.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return const Center(
        child: Text(
          'No lyrics found for this track.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      );
    }

    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
        child: Text(
          lyrics.plainLyrics ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            height: 1.8,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _lyricsScrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, idx) {
        final line = lyrics.lines[idx];
        final isActive = idx == player.activeLyricIndex;

        return InkWell(
          onTap: () {
            player.seek(Duration(milliseconds: line.timeMs));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isActive ? 20 : 16,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                color: isActive ? AppTheme.neon : Colors.white24,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueView(PlayerProvider player) {
    final queue = player.queue;
    final currentIdx = player.currentIndex;

    if (queue.isEmpty) {
      return const Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UP NEXT (${queue.length} TRACKS)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textMuted,
                ),
              ),
              const Text(
                'Tap song to switch',
                style: TextStyle(fontSize: 11, color: AppTheme.cyan),
              ),
            ],
          ),
        ),
        if (player.isLoadingRadio)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.neon.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.neon.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: const [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neon),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'INFINITE RADIO • Curating relatable songs...',
                      style: TextStyle(
                        color: AppTheme.neon,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _queueScrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: queue.length,
            itemBuilder: (context, idx) {
              final stem = queue[idx];
              final isPlayingThis = idx == currentIdx;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isPlayingThis ? AppTheme.neon.withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isPlayingThis ? Border.all(color: AppTheme.neon.withValues(alpha: 0.3)) : null,
                ),
                child: ListTile(
                  dense: true,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: stem.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(imageUrl: stem.artworkUrl, fit: BoxFit.cover)
                          : Container(
                              color: AppTheme.bgElevated,
                              child: const Icon(Icons.music_note, size: 20, color: Colors.white54),
                            ),
                    ),
                  ),
                  title: Text(
                    stem.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isPlayingThis ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13.5,
                      color: isPlayingThis ? AppTheme.neon : Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    stem.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  trailing: isPlayingThis
                      ? const Icon(Icons.equalizer_rounded, color: AppTheme.neon, size: 20)
                      : Text(
                          '#${idx + 1}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                  onTap: () => player.playFromQueue(idx),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
