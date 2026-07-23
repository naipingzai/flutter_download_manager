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

  /// 当前正在执行的任务ID（供下载过程中更新状态用）
  static String? _activeTaskId;

  /// 更新当前任务标题（下载过程中调用，显示进度日志）
  static void updateTaskStatus(String status) {
    if (_activeTaskId == null) return;
    final task = _taskManager.getById(_activeTaskId!);
    if (task == null) return;
    _taskManager.updateTask(task.copyWith(title: status));
  }

  static Future<Map<String, dynamic>> executeTask({
    required String link,
    required String savePath,
    required String source,
    required String type,
    required Future<Map<String, dynamic>> Function(
            void Function(String status) updateStatus)
        execute,
  }) async {
    // 去重：如果同 URL 的任务已完成或正在下载，不重复创建
    final existing = _taskManager.findByUrl(link);
    if (existing != null) {
      if (existing.status == TaskStatus.completed) {
        return {'success': true, 'title': existing.title, 'message': '已下载过'};
      }
      if (existing.status == TaskStatus.downloading) {
        return {'success': false, 'message': '该链接正在下载中'};
      }
    }

    final taskId = _uuid.v4();
    _activeTaskId = taskId;

    final task = DownloadTask(
      id: taskId,
      title: '🔍 解析链接中...',
      url: link,
      type: type,
      status: TaskStatus.downloading,
      source: source,
    );
    await _taskManager.addTask(task);

    void updateStatus(String status) {
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        _taskManager.updateTask(cur.copyWith(title: status));
      }
    }

    try {
      final result = await execute(updateStatus);

      // 检查任务状态
      final cur = _taskManager.getById(taskId);
      if (cur == null) {
        _activeTaskId = null;
        return {'success': false, 'message': '已取消'};
      }
      if (cur.status == TaskStatus.paused) {
        _activeTaskId = null;
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
          title: '✅ $title',
          status: TaskStatus.completed,
          totalSize: size,
          downloadedSize: size,
          filePath: filePath,
        ));
      } else {
        await _taskManager.updateTask(cur.copyWith(
          title: '❌ ${result['message'] ?? '下载失败'}',
          status: TaskStatus.failed,
          errorMessage: result['message']?.toString() ?? '下载失败',
        ));
      }
      _activeTaskId = null;
      return result;
    } catch (e) {
      final cur = _taskManager.getById(taskId);
      if (cur != null) {
        await _taskManager.updateTask(cur.copyWith(
            title: '❌ $e',
            status: TaskStatus.failed,
            errorMessage: e.toString()));
      }
      _activeTaskId = null;
      return {'success': false, 'message': e.toString()};
    }
  }

  static String toJsonString(Map<String, dynamic> data) => jsonEncode(data);
}
