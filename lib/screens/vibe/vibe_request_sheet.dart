import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/stem.dart';
import '../../providers/search_provider.dart';
import '../../providers/vault_provider.dart';
import '../../providers/vibe_provider.dart';
import '../../services/link_resolver_service.dart';
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

class _VibeRequestSheetState extends State<VibeRequestSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LinkResolverService _linkResolver = LinkResolverService();
  final Set<String> _requestedStemIds = {};

  Playlist? _selectedPlaylist;
  bool _isResolvingLink = false;
  String? _linkError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != 0) {
        _focusNode.unfocus();
      }
      if (mounted) setState(() {});
    });

    // Clear stale search results from ExploreScreen so we start fresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SearchProvider>().clearSearch();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _triggerSearch(String query, SearchProvider search) {
    final text = query.trim();
    if (text.isEmpty) return;
    _focusNode.unfocus();

    if (_linkResolver.isSupported(text)) {
      _resolveAndHandleLink(text);
    } else {
      search.executeSearch(text);
    }
  }

  Future<void> _resolveAndHandleLink(String url) async {
    setState(() {
      _isResolvingLink = true;
      _linkError = null;
    });

    try {
      final result = await _linkResolver.resolve(url);
      if (!mounted) return;

      final vibe = context.read<VibeProvider>();
      if (result.type == LinkResultType.track && result.track != null) {
        if (vibe.isHost) {
          _showHostSongActions(context, result.track!, vibe);
        } else {
          vibe.suggestSong(result.track!);
          _showSuggestedToast(result.track!.title);
        }
      } else if (result.type == LinkResultType.playlist && result.playlist != null) {
        setState(() {
          _selectedPlaylist = result.playlist;
          _tabController.animateTo(2);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _linkError = 'Could not resolve link: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingLink = false;
        });
      }
    }
  }

  void _showSuggestedToast(String title) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.cyan, width: 0.8),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.cyan, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Requested "$title" to Host',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
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
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final vibe = context.watch<VibeProvider>();
    final vault = context.watch<VaultProvider>();
    final isHost = vibe.isHost;

    return PopScope(
      canPop: _selectedPlaylist == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedPlaylist != null) {
          setState(() => _selectedPlaylist = null);
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppTheme.borderHairline)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Top Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Row(
                  children: [
                    Icon(
                      isHost ? Icons.library_music_rounded : Icons.queue_music_rounded,
                      color: isHost ? AppTheme.neon : AppTheme.cyan,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHost ? 'Add Music to Party' : 'Request Song for Party',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isHost
                                ? 'Play directly, play next, or add to queue'
                                : 'Suggest songs to the room host',
                            style: TextStyle(
                              color: isHost
                                  ? AppTheme.neon.withValues(alpha: 0.8)
                                  : AppTheme.cyan.withValues(alpha: 0.8),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Navigation Tabs: Search | Liked | Playlists
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderHairline),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: isHost
                            ? AppTheme.neon.withValues(alpha: 0.2)
                            : AppTheme.cyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isHost ? AppTheme.neon : AppTheme.cyan,
                          width: 1,
                        ),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: isHost ? AppTheme.neon : AppTheme.cyan,
                      unselectedLabelColor: AppTheme.textMuted,
                      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      dividerColor: Colors.transparent,
                      tabs: [
                        const Tab(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_rounded, size: 15),
                              SizedBox(width: 6),
                              Text('Search'),
                            ],
                          ),
                        ),
                        Tab(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.favorite_rounded, size: 15),
                              const SizedBox(width: 6),
                              Text('Liked (${vault.favorites.length})'),
                            ],
                          ),
                        ),
                        Tab(
                          height: 40,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.playlist_play_rounded, size: 17),
                              const SizedBox(width: 6),
                              Text('Playlists (${vault.playlists.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Search
                  _buildSearchTab(context, search, vibe, isHost),

                  // Tab 2: Liked Songs (Favorites)
                  _buildFavoritesTab(context, vault, vibe, isHost),

                  // Tab 3: Playlists
                  _buildPlaylistsTab(context, vault, vibe, isHost),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  // =========================================================================
  // TAB 1: Search
  // =========================================================================
  Widget _buildSearchTab(
    BuildContext context,
    SearchProvider search,
    VibeProvider vibe,
    bool isHost,
  ) {
    final isLink = _linkResolver.isSupported(_searchCtrl.text);

    return Column(
      children: [
        // Search Input Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isHost
                    ? AppTheme.neon.withValues(alpha: 0.3)
                    : AppTheme.cyan.withValues(alpha: 0.3),
              ),
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, or paste Spotify link...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                prefixIcon: IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    color: isHost ? AppTheme.neon : AppTheme.cyan,
                    size: 20,
                  ),
                  onPressed: () => _triggerSearch(_searchCtrl.text, search),
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          search.clearSearch();
                          setState(() {});
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (text) {
                setState(() {});
                if (!_linkResolver.isSupported(text)) {
                  search.updateSuggestions(text);
                }
              },
              onSubmitted: (query) => _triggerSearch(query, search),
            ),
          ),
        ),

        // Instant Link Import Card
        if (isLink)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: InkWell(
              onTap: () => _resolveAndHandleLink(_searchCtrl.text),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.neon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.neon.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: AppTheme.neon, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Import track/playlist from link',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_isResolvingLink)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.neon),
                      )
                    else
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: AppTheme.neon, size: 12),
                  ],
                ),
              ),
            ),
          ),

        if (_linkError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              _linkError!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 11.5),
            ),
          ),

        // Autocomplete suggestions (when typing and no search executed yet)
        if (search.suggestions.isNotEmpty &&
            search.searchResults.isEmpty &&
            !search.isLoading)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: search.suggestions.length,
              itemBuilder: (context, idx) {
                final suggestion = search.suggestions[idx];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.search_rounded,
                      color: AppTheme.textMuted, size: 16),
                  title: Text(
                    suggestion,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  trailing: const Icon(Icons.north_west_rounded,
                      color: Colors.white24, size: 14),
                  onTap: () {
                    _searchCtrl.text = suggestion;
                    search.executeSearch(suggestion);
                  },
                );
              },
            ),
          )
        else
          // Search Results or Status
          Expanded(
            child: _buildSearchContent(context, search, vibe, isHost),
          ),
      ],
    );
  }

  Widget _buildSearchContent(
    BuildContext context,
    SearchProvider search,
    VibeProvider vibe,
    bool isHost,
  ) {
    if (search.isLoading || _isResolvingLink) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: isHost ? AppTheme.neon : AppTheme.cyan,
            ),
            const SizedBox(height: 12),
            Text(
              _isResolvingLink ? 'Resolving link...' : 'Searching music...',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    if (search.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 44, color: AppTheme.danger),
              const SizedBox(height: 10),
              Text(
                search.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bgElevated,
                  foregroundColor: AppTheme.neon,
                  side: const BorderSide(color: AppTheme.neon),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Search',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _triggerSearch(_searchCtrl.text, search),
              ),
            ],
          ),
        ),
      );
    }

    if (search.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 48,
              color: isHost
                  ? AppTheme.neon.withValues(alpha: 0.2)
                  : AppTheme.cyan.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 10),
            Text(
              isHost
                  ? 'Search songs to play or queue in the party'
                  : 'Search any song to suggest to the host',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: search.searchResults.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, idx) {
        final stem = search.searchResults[idx];
        return _buildSongItem(context, stem, vibe, isHost);
      },
    );
  }

  // =========================================================================
  // TAB 2: Liked Songs (Favorites)
  // =========================================================================
  Widget _buildFavoritesTab(
    BuildContext context,
    VaultProvider vault,
    VibeProvider vibe,
    bool isHost,
  ) {
    final favorites = vault.favorites;

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.favorite_border_rounded, size: 48, color: Colors.white12),
            SizedBox(height: 10),
            Text(
              'No liked songs yet',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Like songs across ShreyX to quickly access them in parties',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (isHost)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neon.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.neon,
                      side: const BorderSide(color: AppTheme.neon, width: 1),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      'Play All Liked (${favorites.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    onPressed: () {
                      if (favorites.isNotEmpty) {
                        vibe.hostPlayNow(favorites.first);
                        for (int i = 1; i < favorites.length; i++) {
                          vibe.hostAddToQueue(favorites[i]);
                        }
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: favorites.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, idx) {
              final stem = favorites[idx];
              return _buildSongItem(context, stem, vibe, isHost);
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 3: Playlists
  // =========================================================================
  Widget _buildPlaylistsTab(
    BuildContext context,
    VaultProvider vault,
    VibeProvider vibe,
    bool isHost,
  ) {
    if (_selectedPlaylist != null) {
      final pl = _selectedPlaylist!;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedPlaylist = null;
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pl.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      Text(
                        '${pl.stems.length} songs',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (isHost && pl.stems.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neon.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.neon,
                      side: const BorderSide(color: AppTheme.neon, width: 0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Play All',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11.5)),
                    onPressed: () {
                      vibe.hostPlayNow(pl.stems.first);
                      for (int i = 1; i < pl.stems.length; i++) {
                        vibe.hostAddToQueue(pl.stems[i]);
                      }
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: pl.stems.isEmpty
                ? const Center(
                    child: Text(
                      'Playlist is empty',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: pl.stems.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, idx) {
                      final stem = pl.stems[idx];
                      return _buildSongItem(context, stem, vibe, isHost);
                    },
                  ),
          ),
        ],
      );
    }

    final playlists = vault.playlists;

    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.playlist_play_rounded, size: 48, color: Colors.white12),
            SizedBox(height: 10),
            Text(
              'No playlists found',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Create playlists or import Spotify playlists in Library',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: playlists.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, idx) {
        final pl = playlists[idx];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: pl.artworkUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: pl.artworkUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _fallbackCover(),
                  )
                : _fallbackCover(),
          ),
          title: Text(
            pl.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          subtitle: Text(
            '${pl.stems.length} songs',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          onTap: () {
            _focusNode.unfocus();
            setState(() {
              _selectedPlaylist = pl;
            });
          },
        );
      },
    );
  }

  // =========================================================================
  // SONG ITEM BUILDER (Shared across Search, Favorites, and Playlists)
  // =========================================================================
  Widget _buildSongItem(
    BuildContext context,
    Stem stem,
    VibeProvider vibe,
    bool isHost,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      onTap: () {
        if (isHost) {
          _showHostSongActions(context, stem, vibe);
        } else {
          if (!_requestedStemIds.contains(stem.id)) {
            setState(() {
              _requestedStemIds.add(stem.id);
            });
            vibe.suggestSong(stem);
            _showSuggestedToast(stem.title);
          }
        }
      },
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: stem.artworkUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: stem.artworkUrl,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallbackCover(),
              )
            : _fallbackCover(),
      ),
      title: Text(
        stem.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        '${stem.artistName} • ${_formatDuration(stem.durationSec)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
      ),
      trailing: isHost
          ? _buildHostActionButtons(context, stem, vibe)
          : _buildMemberActionButton(context, stem, vibe),
    );
  }

  /// Host Trailing: Direct Play button + More Options Menu
  Widget _buildHostActionButtons(
    BuildContext context,
    Stem stem,
    VibeProvider vibe,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_circle_fill_rounded,
              color: AppTheme.neon, size: 28),
          tooltip: 'Play Now',
          onPressed: () {
            vibe.hostPlayNow(stem);
            _showToast('Playing "${stem.title}"');
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
          color: AppTheme.bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppTheme.borderHairline),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'play_now',
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: AppTheme.neon, size: 18),
                  SizedBox(width: 8),
                  Text('Play Now',
                      style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'play_next',
              child: Row(
                children: [
                  Icon(Icons.playlist_play_rounded, color: AppTheme.cyan, size: 18),
                  SizedBox(width: 8),
                  Text('Play Next',
                      style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'add_queue',
              child: Row(
                children: [
                  Icon(Icons.queue_music_rounded,
                      color: Colors.amberAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Add to Queue',
                      style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
            ),
          ],
          onSelected: (action) {
            if (action == 'play_now') {
              vibe.hostPlayNow(stem);
              _showToast('Playing "${stem.title}"');
            } else if (action == 'play_next') {
              vibe.hostPlayNext(stem);
              _showToast('Playing "${stem.title}" next');
            } else if (action == 'add_queue') {
              vibe.hostAddToQueue(stem);
              _showToast('Added "${stem.title}" to queue');
            }
          },
        ),
      ],
    );
  }

  /// Host Bottom Sheet with friendly large action cards
  void _showHostSongActions(BuildContext context, Stem stem, VibeProvider vibe) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppTheme.neon, width: 0.8)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: stem.artworkUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: stem.artworkUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover)
                        : _fallbackCover(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                        Text(
                          stem.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Action 1: Play Now
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neon.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: AppTheme.neon, size: 22),
                ),
                title: const Text('Play Now',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5)),
                subtitle: const Text('Starts playing immediately across party',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  vibe.hostPlayNow(stem);
                  _showToast('Playing "${stem.title}"');
                },
              ),

              // Action 2: Play Next
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.playlist_play_rounded,
                      color: AppTheme.cyan, size: 22),
                ),
                title: const Text('Play Next',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5)),
                subtitle: const Text('Plays immediately after current song',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  vibe.hostPlayNext(stem);
                  _showToast('Playing "${stem.title}" next');
                },
              ),

              // Action 3: Add to Queue
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.queue_music_rounded,
                      color: Colors.amberAccent, size: 22),
                ),
                title: const Text('Add to Queue',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5)),
                subtitle: const Text('Appends to the end of party queue',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  vibe.hostAddToQueue(stem);
                  _showToast('Added "${stem.title}" to queue');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Member Trailing: Suggest Button with persistent Sent state
  Widget _buildMemberActionButton(
    BuildContext context,
    Stem stem,
    VibeProvider vibe,
  ) {
    final isRequested = _requestedStemIds.contains(stem.id);
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isRequested
            ? AppTheme.cyan.withValues(alpha: 0.25)
            : AppTheme.cyan.withValues(alpha: 0.15),
        foregroundColor: isRequested ? Colors.white : AppTheme.cyan,
        side: BorderSide(
          color: isRequested ? AppTheme.cyan : AppTheme.cyan.withValues(alpha: 0.5),
          width: 1,
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: Icon(
        isRequested ? Icons.check_circle_rounded : Icons.send_rounded,
        size: 13,
        color: isRequested ? AppTheme.neon : AppTheme.cyan,
      ),
      label: Text(
        isRequested ? 'Sent' : 'Request',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: isRequested ? AppTheme.neon : AppTheme.cyan,
        ),
      ),
      onPressed: isRequested
          ? null
          : () {
              setState(() {
                _requestedStemIds.add(stem.id);
              });
              vibe.suggestSong(stem);
              _showSuggestedToast(stem.title);
            },
    );
  }

  Widget _fallbackCover() {
    return Container(
      width: 46,
      height: 46,
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
