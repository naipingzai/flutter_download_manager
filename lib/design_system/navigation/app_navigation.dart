import 'package:flutter/material.dart';

/// App 一级导航项
class AppNavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const AppNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });
}

/// AppNavigation 布局类型
enum AppNavigationLayout { bar, rail, extendedRail }

/// AppNavigation — Design System 一级导航
///
/// API 保持统一，业务层不感知差异：
/// - Phone (< 600dp) → Material NavigationBar（底部）
/// - Tablet (>= 600dp) → Material NavigationRail（侧边）
class AppNavigation extends StatelessWidget {
  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final AppNavigationLayout layout;

  const AppNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.layout = AppNavigationLayout.bar,
  });

  bool get _isRail => layout != AppNavigationLayout.bar;

  @override
  Widget build(BuildContext context) {
    if (_isRail) {
      return NavigationRail(
        selectedIndex: currentIndex,
        onDestinationSelected: onChanged,
        labelType: layout == AppNavigationLayout.extendedRail
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        extended: layout == AppNavigationLayout.extendedRail,
        destinations: items
            .map(
              (it) => NavigationRailDestination(
                icon: Icon(it.icon),
                selectedIcon: Icon(it.selectedIcon ?? it.icon),
                label: Text(it.label),
              ),
            )
            .toList(),
      );
    }
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onChanged,
      destinations: items
          .map(
            (it) => NavigationDestination(
              icon: Icon(it.icon),
              selectedIcon: Icon(it.selectedIcon ?? it.icon),
              label: it.label,
            ),
          )
          .toList(),
    );
  }
}

/// AppNavigationScaffold — 自动根据屏幕宽度选择布局
///
/// 业务代码：
/// ```
/// AppNavigationScaffold(
///   items: [...],
///   currentIndex: 0,
///   onChanged: (i) {},
///   body: MyPage(),
/// )
/// ```
///
/// 通过 [showNavigation] 控制是否显示导航栏（默认 true）
class AppNavigationScaffold extends StatelessWidget {
  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final Widget body;
  final AppBar? appBar;
  final bool showNavigation;
  static const double tabletBreakpoint = 600;

  const AppNavigationScaffold({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    required this.body,
    this.appBar,
    this.showNavigation = true,
  });

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  Widget build(BuildContext context) {
    if (_isTablet(context)) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            if (showNavigation)
              AppNavigation(
                items: items,
                currentIndex: currentIndex,
                onChanged: onChanged,
                layout: AppNavigationLayout.extendedRail,
              ),
            if (showNavigation) const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: showNavigation
          ? AppNavigation(
              items: items,
              currentIndex: currentIndex,
              onChanged: onChanged,
              layout: AppNavigationLayout.bar,
            )
          : null,
    );
  }
}
