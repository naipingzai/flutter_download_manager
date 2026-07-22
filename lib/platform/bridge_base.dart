import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../model/download_task.dart';
import '../service/download_task_manager.dart';

/// 平台 Bridge 基类
abstract class BridgeBase {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();

  static Future<Map<String, dynamic>> executeTask({
    required String link,
    required String savePath,
    required String source,
    required String type,
    required Future<Map<String, dynamic>> Function() execute,
  }) async {
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

      // 下载完成后检查：如果用户已暂停/删除，不覆盖状态
      final cur = _taskManager.getById(taskId);
      if (cur == null) {
        return {'success': false, 'message': '已取消'};
      }
      if (cur.status == TaskStatus.paused) {
        return {'success': false, 'message': '已暂停'};
      }

      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      if (success) {
        var size = result['size'] as int? ?? 0;
        final filePath = result['path']?.toString() ?? '';
        if (size == 0 && filePath.isEmpty) {
          try {
            final dir = Directory(savePath);
            if (await dir.exists()) {
              int total = 0;
              await for (final entity in dir.list(recursive: true)) {
                if (entity is File) total += await entity.length();
              }
              size = total;
            }
          } catch (_) {}
        }
        await _taskManager.updateTask(cur.copyWith(
          title: title,
          status: TaskStatus.completed,
          totalSize: size,
          downloadedSize: size,
          filePath: filePath,
        ));
      } else {
        await _taskManager.updateTask(cur.copyWith(
          title: title,
          status: TaskStatus.failed,
          errorMessage: result['message']?.toString() ?? '下载失败',
        ));
      }
      return result;
    } catch (e) {
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        await _taskManager.updateTask(
            cur.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  static String toJsonString(Map<String, dynamic> data) => jsonEncode(data);
}
