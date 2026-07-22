import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    // 去重：如果同 URL 的任务已完成，直接返回成功
    final existing = _taskManager.findByUrl(link);
    if (existing != null && existing.status == TaskStatus.completed) {
      return {'success': true, 'title': existing.title, 'message': '已下载过'};
    }

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
        var size = result['size'] as int? ?? 0;
        final filePath = result['path']?.toString() ?? '';

        // 如果 size 为空（图集），扫描下载目录计算总大小
        if (size == 0 && filePath.isEmpty) {
          try {
            final dir = Directory(savePath);
            if (await dir.exists()) {
              int total = 0;
              await for (final entity in dir.list(recursive: true)) {
                if (entity is File) {
                  total += await entity.length();
                }
              }
              size = total;
            }
          } catch (_) {}
        }

        await _taskManager.updateTask(
          task.copyWith(
            title: title,
            status: TaskStatus.completed,
            totalSize: size,
            downloadedSize: size,
            filePath: filePath,
          ),
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
