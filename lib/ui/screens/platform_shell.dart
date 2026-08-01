import 'package:flutter/material.dart';
import 'terminal_screen.dart';
import 'settings_screen.dart';
import 'cookie_manage_screen.dart';

/// 平台内部导航框架
/// 主要界面为终端模拟器，设置页保留
class PlatformShell extends StatefulWidget {
  final String platformName;
  final String platformId;
  final String? sharedLink;
  final VoidCallback onBackToHome;

  const PlatformShell({
    super.key,
    required this.platformName,
    required this.platformId,
    this.sharedLink,
    required this.onBackToHome,
  });

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int _currentIndex = 0;
  bool _showingCookiePage = false;

  String get _currentTitle {
    if (_showingCookiePage) return '${widget.platformName} Cookie';
    switch (_currentIndex) {
      case 0:
        return '${widget.platformName}终端';
      case 1:
        return '设置';
      default:
        return widget.platformName;
    }
  }

  bool get _showBottomBar => !_showingCookiePage;

  void _navigateToCookie() {
    setState(() => _showingCookiePage = true);
  }

  int _settingsRefreshKey = 0;

  void _popCookie() {
    setState(() {
      _showingCookiePage = false;
      _settingsRefreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_showingCookiePage) {
              _popCookie();
            } else {
              widget.onBackToHome();
            }
          },
        ),
      ),
      bottomNavigationBar: _showBottomBar
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.terminal),
                  label: '终端',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            )
          : null,
      body: _showingCookiePage
          ? CookieManageScreen(
              platform: widget.platformId,
              platformName: widget.platformName,
            )
          : IndexedStack(
              index: _currentIndex,
              children: [
                TerminalScreen(
                  platformId: widget.platformId,
                  platformName: widget.platformName,
                ),
                SettingsScreen(
                  key: ValueKey(_settingsRefreshKey),
                  platform: widget.platformId,
                  onCookie: _navigateToCookie,
                ),
              ],
            ),
    );
  }
}
