import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_service.dart';

/// 小红书下载桥接层 - 通过 PythonService FFI 调用 xhs_bridge.py
class XhsBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;

  /// 解析小红书链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
        id: taskId,
        title: '解析中: $link',
        url: link,
        status: TaskStatus.downloading,
        source: 'xhs');
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callXhsBridge(
          'parse_link', jsonEncode([link, savePath, taskId]));
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      if (success) {
        await _taskManager.updateTask(
            task.copyWith(title: title, status: TaskStatus.completed));
        return {'success': true, 'title': title};
      } else {
        await _taskManager.updateTask(task.copyWith(
            title: title,
            status: TaskStatus.failed,
            errorMessage: result['message'] ?? '下载失败'));
        return {'success': false, 'message': result['message'] ?? '下载失败'};
      }
    } catch (e) {
      await _taskManager.updateTask(
          task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 检测笔记信息
  static Future<String> detectLinkInfo(String link) async {
    return _python.callXhsBridge('detect_note_info', jsonEncode([link]));
  }

  /// 设置 Cookie
  static void setCookie(String cookie) {
    _python.callXhsBridge('set_cookie', jsonEncode([cookie]));
  }

  /// 暂停任务
  static void pauseTask(String taskId) {
    _python.callXhsBridge('pause_task', jsonEncode([taskId]));
  }

  /// 恢复任务
  static void resumeTask(String taskId) {
    _python.callXhsBridge('resume_task', jsonEncode([taskId]));
  }
}
