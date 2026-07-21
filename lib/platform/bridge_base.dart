import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../model/download_task.dart';
import '../service/download_task_manager.dart';
import '../service/python_service.dart';

/// 平台 Bridge 基类，提取 DouyinBridge / XhsBridge 的公共逻辑
abstract class BridgeBase {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;

  /// 创建下载任务并执行操作
  static Future<Map<String, dynamic>> executeTask({
    required String link,
    required String savePath,
    required String source,
    required String type,
    required Future<Map<String, dynamic>> Function() execute,
  }) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '解析中: $link',
      url: link,
      type: type,
      status: TaskStatus.downloading,
      source: source,
    );
    await _taskManager.addTask(task);

    try {
      final result = await execute();
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      if (success) {
        await _taskManager.updateTask(
          task.copyWith(title: title, status: TaskStatus.completed),
        );
      } else {
        await _taskManager.updateTask(
          task.copyWith(
            title: title,
            status: TaskStatus.failed,
            errorMessage: result['message']?.toString() ?? '下载失败',
          ),
        );
      }
      return result;
    } catch (e) {
      await _taskManager.updateTask(
        task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()),
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Python 调用包装
  static Map<String, dynamic> callPython(
    String module,
    String function,
    List<dynamic> args,
  ) {
    final resultStr = _python.callFunction(module, function, jsonEncode(args));
    return jsonDecode(resultStr) as Map<String, dynamic>;
  }
}
