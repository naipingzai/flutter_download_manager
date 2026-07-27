import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/task_manager/download_task_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final taskManager = DownloadTaskManager();
  try {
    await taskManager.init();
  } catch (e) {
    debugPrint('TaskManager init failed: $e');
  }

  runApp(
    ChangeNotifierProvider.value(
      value: taskManager,
      child: const DownloadManagerApp(),
    ),
  );
}
