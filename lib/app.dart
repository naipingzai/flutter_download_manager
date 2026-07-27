import 'package:flutter/material.dart';

import 'design_system/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/platform_shell.dart';

/// 应用根 Widget — 仅负责 MaterialApp 与路由
class DownloadManagerApp extends StatelessWidget {
  const DownloadManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '下载',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(null),
      darkTheme: AppTheme.darkTheme(null),
      themeMode: ThemeMode.system,
      home: const _RootNavigator(),
    );
  }
}

/// 根导航：home ↔ 平台容器
class _RootNavigator extends StatefulWidget {
  const _RootNavigator();

  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> {
  PlatformMode _platformMode = PlatformMode.home;
  String? _sharedLink;

  void _enterPlatform(PlatformMode mode, String? sharedLink) {
    setState(() {
      _platformMode = mode;
      _sharedLink = sharedLink;
    });
  }

  void _exitPlatform() {
    setState(() {
      _platformMode = PlatformMode.home;
      _sharedLink = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_platformMode) {
      case PlatformMode.home:
        return HomeScreen(
          onSelectDouyin: () => _enterPlatform(PlatformMode.douyin, null),
          onSelectXhs: () => _enterPlatform(PlatformMode.xhs, null),
        );
      case PlatformMode.douyin:
        return PlatformShell(
          platformName: '抖音',
          platformId: 'douyin',
          sharedLink: _sharedLink,
          onBackToHome: _exitPlatform,
        );
      case PlatformMode.xhs:
        return PlatformShell(
          platformName: '小红书',
          platformId: 'xhs',
          sharedLink: _sharedLink,
          onBackToHome: _exitPlatform,
        );
    }
  }
}

/// 平台模式
enum PlatformMode { home, douyin, xhs }
