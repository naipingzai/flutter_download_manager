import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_service.dart';
import '../../service/http_download_service.dart';

/// 小红书下载桥接层
/// 优先使用 Python (Linux/Android)，Python 不可用时回退到纯 Dart HTTP (iOS/macOS)
class XhsBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;
  static final HttpDownloadService _http = HttpDownloadService.instance;

  static bool get _usePython => _python.isReady;

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
      Map<String, dynamic> result;

      if (_usePython) {
        // Python 路径
        final resultStr = _python.callXhsBridge(
            'parse_link', jsonEncode([link, savePath, taskId]));
        result = jsonDecode(resultStr) as Map<String, dynamic>;
      } else {
        // HTTP 回退路径
        result = await _http.downloadXhsNote(link, savePath);
      }

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
    if (_usePython) {
      return _python.callXhsBridge('detect_note_info', jsonEncode([link]));
    }
    return '{"success":true,"message":"HTTP模式：请直接粘贴链接下载"}';
  }

  /// 设置 Cookie
  static void setCookie(String cookie) {
    _http.setXhsCookie(cookie);
    if (_usePython) {
      _python.callXhsBridge('set_cookie', jsonEncode([cookie]));
    }
  }

  /// 暂停任务
  static void pauseTask(String taskId) {
    if (_usePython) {
      _python.callXhsBridge('pause_task', jsonEncode([taskId]));
    }
  }

  /// 恢复任务
  static void resumeTask(String taskId) {
    if (_usePython) {
      _python.callXhsBridge('resume_task', jsonEncode([taskId]));
    }
  }
}
