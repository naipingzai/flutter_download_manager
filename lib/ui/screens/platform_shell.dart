import 'package:flutter/material.dart';
import 'download_screen.dart';
import 'tasks_screen.dart';
import 'settings_screen.dart';
import 'cookie_manage_screen.dart';

/// 平台内部导航框架 - 完全复刻原项目 PlatformShell
/// 包含: 顶部 AppBar (返回箭头 + 标题) + 底部 NavigationBar (下载/任务/设置)
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
  int _tasksScrollToTop = 0;
  bool _showingCookiePage = false;

  String get _currentTitle {
    if (_showingCookiePage) return '${widget.platformName} Cookie';
    switch (_currentIndex) {
      case 0:
        return '${widget.platformName}下载';
      case 1:
        return '下载任务';
      case 2:
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
      // 顶部 AppBar - 对应原项目 TopAppBar + 返回箭头
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
      // 底部 NavigationBar - 对应原项目的 NavigationBar 三个 tab
      bottomNavigationBar: _showBottomBar
          ? NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                if (index == _currentIndex && index == 1) {
                  // 双击任务图标滚动到顶部
                  setState(() => _tasksScrollToTop++);
                } else {
                  setState(() => _currentIndex = index);
                }
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.download),
                  label: '下载',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.list),
                  label: '任务',
                ),
                const NavigationDestination(
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
                DownloadScreen(
                  platformId: widget.platformId,
                  platformName: widget.platformName,
                  sharedLink: widget.sharedLink,
                ),
                TasksScreen(
                  platform: widget.platformId,
                  scrollToTop: _tasksScrollToTop,
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
