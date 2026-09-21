import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/vibe_provider.dart';
import '../services/link_resolver_service.dart';
import '../theme/app_theme.dart';
import '../widgets/link_import_sheet.dart';
import '../widgets/track_row.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final LinkResolverService _linkResolver = LinkResolverService();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final isLinkInput = _linkResolver.isSupported(_searchCtrl.text);

    return PopScope(
      canPop: _searchCtrl.text.isEmpty && search.searchResults.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchCtrl.text.isNotEmpty || search.searchResults.isNotEmpty) {
          _searchCtrl.clear();
          search.clearSearch();
          setState(() {});
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Search & Explore'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link_rounded, color: AppTheme.neon),
              tooltip: 'Import Playlist / Track Link',
              onPressed: () => LinkImportSheet.show(context),
            ),
          ],
        ),
        body: Column(
        children: [
          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF13131D),
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: AppTheme.borderHairline),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, or paste link...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.neon),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                          onPressed: () {
                            _searchCtrl.clear();
                            search.clearSearch();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (text) {
                  setState(() {});
                  if (!_linkResolver.isSupported(text)) {
                    search.updateSuggestions(text);
                  }
                },
                onSubmitted: (text) {
                  if (_linkResolver.isSupported(text)) {
                    LinkImportSheet.show(context, initialUrl: text.trim());
                  } else {
                    search.executeSearch(text);
                  }
                },
              ),
            ),
          ),

          // Instant Link Import Card (when URL is pasted)
          if (isLinkInput)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: InkWell(
                onTap: () => LinkImportSheet.show(context, initialUrl: _searchCtrl.text.trim()),
                borderRadius: BorderRadius.circular(14.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.neon.withValues(alpha: 0.18),
                        AppTheme.cyan.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14.0),
                    border: Border.all(color: AppTheme.neon.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppTheme.neon, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Link Detected • Tap to Import',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              'Import track or playlist from Spotify / YouTube',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.neon,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Import',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Autocomplete suggestions
          if (search.suggestions.isNotEmpty && search.searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF13131D),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: AppTheme.borderHairline),
                ),
                child: Column(
                  children: search.suggestions.map((s) {
                    return InkWell(
                      onTap: () {
                        _searchCtrl.text = s;
                        search.executeSearch(s);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 16, color: AppTheme.textMuted),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s,
                                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Loading spinner
          if (search.isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: AppTheme.neon),
            ),

          // Error banner
          if (search.error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                search.error!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
              ),
            ),

          // Search Results
          Expanded(
            child: search.searchResults.isEmpty && !search.isLoading
                ? _buildEmptyState(search)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: search.searchResults.length,
                    itemBuilder: (context, idx) {
                      final stem = search.searchResults[idx];
                      return TrackRow(
                        stem: stem,
                        onTap: () {
                          final vibe = context.read<VibeProvider>();
                          if (vibe.isInRoom && !vibe.isHost) {
                            _showMemberSongAction(context, stem, vibe);
                          } else {
                            context.read<PlayerProvider>().playWithRadio(stem);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildEmptyState(SearchProvider search) {
    const genres = [
      'Trending Hits',
      'Synthwave',
      'Lo-Fi Chill',
      'Hip Hop',
      'Cyberpunk',
      'Rock Classics',
      'Workout Energy',
      'Bollywood Hits',
      'Acoustic Pop',
    ];

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.youtube_searched_for_rounded, size: 56, color: Colors.white12),
            const SizedBox(height: 12),
            const Text(
              'Explore 100M+ Songs & Streams',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'HQ 160kbps audio streams with background playback & offline vault',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Quick Genre Discovery Pills
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: genres.map((genre) {
                  return ActionChip(
                    backgroundColor: AppTheme.bgElevated,
                    side: const BorderSide(color: AppTheme.borderHairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    label: Text(
                      genre,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      _searchCtrl.text = genre;
                      search.executeSearch(genre);
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.neon, width: 1.2),
                foregroundColor: AppTheme.neon,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text(
                'Import Playlist or Song Link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () => LinkImportSheet.show(context),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showMemberSongAction(BuildContext context, Stem stem, VibeProvider vibe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.sensors_rounded, color: AppTheme.neon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Party Room (${vibe.room?.code})',
                      style: const TextStyle(color: AppTheme.neon, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                stem.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                stem.artistName,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neon,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Suggest to Party Host', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  vibe.suggestSong(stem);
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.bgElevated,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      content: Text('Suggested "${stem.title}" to Host!'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderHairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Play Locally (Leaves Party)'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  vibe.leaveRoom();
                  context.read<PlayerProvider>().playWithRadio(stem);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
