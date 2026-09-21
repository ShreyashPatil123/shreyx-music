import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/mini_player.dart';
import 'discover_screen.dart';
import 'explore_screen.dart';
import 'vault_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<int> _tabHistory = [0];

  static const _channel = MethodChannel('com.shreyx.player/native_stream');

  final List<Widget> _screens = const [
    DiscoverScreen(),
    ExploreScreen(),
    VaultScreen(),
  ];

  void _onTabTapped(int idx) {
    if (_currentIndex == idx) return;
    setState(() {
      _tabHistory.remove(idx);
      _tabHistory.add(idx);
      _currentIndex = idx;
    });
  }

  Future<void> _minimizeApp() async {
    try {
      await _channel.invokeMethod('minimizeApp');
    } catch (_) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If user has navigated between tabs, go back to previous tab
        if (_tabHistory.length > 1) {
          setState(() {
            _tabHistory.removeLast();
            _currentIndex = _tabHistory.last;
          });
          return;
        }

        // 2. If on a non-root tab, go to Discover tab (0)
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _tabHistory.clear();
            _tabHistory.add(0);
          });
          return;
        }

        // 3. Root page (Discover): minimize app to background so music keeps playing!
        await _minimizeApp();
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayer(),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              activeIcon: Icon(Icons.saved_search_rounded),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_special_outlined),
              activeIcon: Icon(Icons.folder_special_rounded),
              label: 'The Vault',
            ),
          ],
        ),
      ),
    );
  }
}
