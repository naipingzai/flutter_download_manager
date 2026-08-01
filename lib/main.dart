import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/task_manager/download_task_manager.dart';
import 'services/python/python_runner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化任务管理器
  final taskManager = DownloadTaskManager();
  try {
    await taskManager.init();
  } catch (e) {
    debugPrint('TaskManager init failed: $e');
  }

  // 初始化内嵌 Python 环境
  try {
    await PythonRunner.instance.isAvailable;
    debugPrint('Python environment initialized');
  } catch (e) {
    debugPrint('Python init failed: $e');
  }

  runApp(
    ChangeNotifierProvider.value(
      value: taskManager,
      child: const DownloadManagerApp(),
    ),
  );
}
