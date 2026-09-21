import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../providers/vault_provider.dart';
import '../services/download_service.dart';
import '../services/link_resolver_service.dart';
import '../theme/app_theme.dart';
import 'track_row.dart';

class LinkImportSheet extends StatefulWidget {
  final String? initialUrl;

  const LinkImportSheet({super.key, this.initialUrl});

  static Future<void> show(BuildContext context, {String? initialUrl}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LinkImportSheet(initialUrl: initialUrl),
    );
  }

  @override
  State<LinkImportSheet> createState() => _LinkImportSheetState();
}

class _LinkImportSheetState extends State<LinkImportSheet> {
  late final TextEditingController _urlCtrl;
  final LinkResolverService _resolver = LinkResolverService();

  bool _isLoading = false;
  String? _error;
  ResolvedLinkResult? _result;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? '');
    if (widget.initialUrl != null && widget.initialUrl!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleResolve();
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleResolve() async {
    final text = _urlCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final res = await _resolver.resolve(text);
      if (mounted) {
        setState(() {
          _result = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  void _handlePlayNow() {
    if (_result == null) return;
    final player = context.read<PlayerProvider>();

    if (_result!.type == LinkResultType.track && _result!.track != null) {
      player.playStem(_result!.track!);
    } else if (_result!.type == LinkResultType.playlist && _result!.playlist != null) {
      final stems = _result!.playlist!.stems;
      if (stems.isNotEmpty) {
        player.playStem(stems.first, queue: stems);
      }
    }
    Navigator.of(context).pop();
  }

  void _handleShufflePlay() {
    if (_result == null) return;
    final player = context.read<PlayerProvider>();

    if (_result!.type == LinkResultType.track && _result!.track != null) {
      player.playStem(_result!.track!);
    } else if (_result!.type == LinkResultType.playlist && _result!.playlist != null) {
      final stems = _result!.playlist!.stems;
      if (stems.isNotEmpty) {
        player.shufflePlay(stems);
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _handleSaveToVault() async {
    if (_result == null) return;
    final vault = context.read<VaultProvider>();

    if (_result!.type == LinkResultType.track && _result!.track != null) {
      await vault.toggleFavorite(_result!.track!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${_result!.track!.title}" to Favorites!'),
            backgroundColor: AppTheme.bgElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (_result!.type == LinkResultType.playlist && _result!.playlist != null) {
      final pl = _result!.playlist!;
      await vault.createPlaylist(
        pl.name,
        description: pl.description,
        stems: pl.stems,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved playlist "${pl.name}" (${pl.stems.length} songs) to Vault!'),
            backgroundColor: AppTheme.bgElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _handleDownloadAll() async {
    if (_result == null) return;
    final downloadService = DownloadService();

    if (_result!.type == LinkResultType.track && _result!.track != null) {
      downloadService.downloadStem(_result!.track!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading track for offline playback...'),
            backgroundColor: AppTheme.bgElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (_result!.type == LinkResultType.playlist && _result!.playlist != null) {
      final pl = _result!.playlist!;
      for (final s in pl.stems) {
        downloadService.downloadStem(
          s,
          playlistId: pl.id,
          playlistTitle: pl.name,
          playlistArtwork: pl.artworkUrl,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading ${pl.stems.length} songs from "${pl.name}" for offline use!'),
            backgroundColor: AppTheme.bgElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF111119),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.borderHairline, width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neon.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.link_rounded, color: AppTheme.neon, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import Music / Playlist',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Spotify & YouTube links supported',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Link Input Row
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181824),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderHairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: const InputDecoration(
                        hintText: 'Paste Spotify or YouTube link here...',
                        hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _handleResolve(),
                    ),
                  ),
                  if (_urlCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.white38),
                      onPressed: () => setState(() {
                        _urlCtrl.clear();
                        _result = null;
                        _error = null;
                      }),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neon,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: _isLoading ? null : _handleResolve,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'Import',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Error banner
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppTheme.danger, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Resolved Content Preview
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161622),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderHairline),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 60,
                        height: 60,
                        color: AppTheme.bgElevated,
                        child: _result!.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _result!.artworkUrl,
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                _result!.type == LinkResultType.track
                                    ? Icons.music_note
                                    : Icons.queue_music,
                                color: AppTheme.neon,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _result!.originalUrl.contains('spotify')
                                  ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                                  : Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _result!.originalUrl.contains('spotify')
                                  ? (_result!.type == LinkResultType.track
                                      ? 'SPOTIFY TRACK'
                                      : 'SPOTIFY PLAYLIST')
                                  : (_result!.type == LinkResultType.track
                                      ? 'YOUTUBE TRACK'
                                      : 'YOUTUBE PLAYLIST'),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: _result!.originalUrl.contains('spotify')
                                    ? const Color(0xFF1DB954)
                                    : const Color(0xFFFF4E4E),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _result!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _result!.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neon,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        _result!.type == LinkResultType.track ? 'Play Now' : 'Play All',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      onPressed: _handlePlayNow,
                    ),
                  ),
                  if (_result!.type == LinkResultType.playlist) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: const Text(
                          'Shuffle',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        onPressed: _handleShufflePlay,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E2C),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white, size: 20),
                    tooltip: 'Save to Vault',
                    onPressed: _handleSaveToVault,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1E2C),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.download_rounded, color: AppTheme.cyan, size: 20),
                    tooltip: 'Download Offline',
                    onPressed: _handleDownloadAll,
                  ),
                ],
              ),

              // If playlist has tracks, show brief sample of first 4 tracks
              if (_result!.type == LinkResultType.playlist && _result!.playlist != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'PREVIEW SONGS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                ..._result!.playlist!.stems.take(4).map(
                      (s) => TrackRow(
                        stem: s,
                        playlistContextId: _result!.playlist!.id,
                        playlistContextTitle: _result!.playlist!.name,
                      ),
                    ),
                if (_result!.playlist!.stems.length > 4)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        '+ ${_result!.playlist!.stems.length - 4} more songs',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
