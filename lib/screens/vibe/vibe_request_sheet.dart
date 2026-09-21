import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/stem.dart';
import '../../providers/search_provider.dart';
import '../../providers/vibe_provider.dart';
import '../../theme/app_theme.dart';

class VibeRequestSheet extends StatefulWidget {
  const VibeRequestSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VibeRequestSheet(),
    );
  }

  @override
  State<VibeRequestSheet> createState() => _VibeRequestSheetState();
}

class _VibeRequestSheetState extends State<VibeRequestSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final vibe = context.read<VibeProvider>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppTheme.borderHairline)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Drag Handle & Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
              child: Row(
                children: [
                  const Icon(Icons.queue_music_rounded, color: AppTheme.neon, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Request a Song for the Party',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: AppTheme.borderHairline),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search YouTube / Spotify tracks...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.neon, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              search.clearSearch();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onSubmitted: (query) {
                    if (query.trim().isNotEmpty) {
                      search.executeSearch(query.trim());
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Content Area
            Expanded(
              child: search.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.neon),
                    )
                  : search.searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.music_note_rounded, size: 48, color: Colors.white12),
                              SizedBox(height: 10),
                              Text(
                                'Search for any song to suggest to the host',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: search.searchResults.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, idx) {
                            final stem = search.searchResults[idx];
                            return _buildSongItem(context, stem, vibe);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongItem(BuildContext context, Stem stem, VibeProvider vibe) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: stem.artworkUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: stem.artworkUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallbackCover(),
              )
            : _fallbackCover(),
      ),
      title: Text(
        stem.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      subtitle: Text(
        '${stem.artistName} • ${_formatDuration(stem.durationSec)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
      ),
      trailing: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.neon.withValues(alpha: 0.15),
          foregroundColor: AppTheme.neon,
          side: const BorderSide(color: AppTheme.neon, width: 1),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        icon: const Icon(Icons.send_rounded, size: 14),
        label: const Text(
          'Suggest',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          vibe.suggestSong(stem);
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.bgElevated,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.neon, width: 0.8),
              ),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.neon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Suggested "${stem.title}" to Host',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      width: 48,
      height: 48,
      color: AppTheme.bgElevated,
      child: const Icon(Icons.music_note, color: Colors.white38, size: 22),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
