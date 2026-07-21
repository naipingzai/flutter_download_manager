import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../model/download_task.dart';
import '../service/download_task_manager.dart';

/// 平台 Bridge 基类 — 全平台统一调用 NativeDownloadService
/// 所有平台（Linux/Android/iOS/macOS/Windows）流程完全相同：
/// 1. 创建 DownloadTask → 2. 调用 NativeDownloadService → 3. 更新任务状态
abstract class BridgeBase {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();

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

  /// 同步结果转 JSON（用于 detect/getStats 这类不需要等待的接口）
  static String toJsonString(Map<String, dynamic> data) => jsonEncode(data);
}
