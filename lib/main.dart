import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'service/download_task_manager.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/platform_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final taskManager = DownloadTaskManager();
  await taskManager.init();

  runApp(
    ChangeNotifierProvider.value(
      value: taskManager,
      child: const DownloadManagerApp(),
    ),
  );
}

/// 平台模式
enum PlatformMode { home, douyin, xhs }

class DownloadManagerApp extends StatelessWidget {
  const DownloadManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '下载管理器',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(null),
      darkTheme: AppTheme.darkTheme(null),
      themeMode: ThemeMode.system,
      home: const MainApp(),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  PlatformMode _platformMode = PlatformMode.home;
  String? _sharedLink;

  @override
  Widget build(BuildContext context) {
    switch (_platformMode) {
      case PlatformMode.home:
        return HomeScreen(
          onSelectDouyin: () =>
              setState(() => _platformMode = PlatformMode.douyin),
          onSelectXhs: () => setState(() => _platformMode = PlatformMode.xhs),
        );
      case PlatformMode.douyin:
        return PlatformShell(
          platformName: '抖音',
          platformId: 'douyin',
          sharedLink: _sharedLink,
          onBackToHome: () => setState(() {
            _platformMode = PlatformMode.home;
            _sharedLink = null;
          }),
        );
      case PlatformMode.xhs:
        return PlatformShell(
          platformName: '小红书',
          platformId: 'xhs',
          sharedLink: _sharedLink,
          onBackToHome: () => setState(() {
            _platformMode = PlatformMode.home;
            _sharedLink = null;
          }),
        );
    }
  }
}
