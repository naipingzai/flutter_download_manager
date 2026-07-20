import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_service.dart';

/// 小红书下载桥接层，对应原项目 XhsPythonBridge
/// 通过 C++ 嵌入的 CPython 解释器调用原始 xhs_bridge.py 脚本
class XhsBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;

  /// 解析链接并下载（对应 xhs_bridge.parse_link）
  static Future<Map<String, dynamic>> parseAndDownload(
    String link,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '解析中: $link',
      url: link,
      status: TaskStatus.downloading,
      source: 'xhs',
    );
    await _taskManager.addTask(task);

    try {
      // 调用 Python xhs_bridge.parse_link(link, save_path, task_id)
      final resultStr = _python.callXhsBridge(
        'parse_link',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;
      final message = result['message']?.toString();

      if (success) {
        await _taskManager.updateTask(
          task.copyWith(title: title, status: TaskStatus.completed),
        );
        return {'success': true, 'title': title};
      } else {
        await _taskManager.updateTask(
          task.copyWith(
            title: title,
            status: TaskStatus.failed,
            errorMessage: message ?? '下载失败',
          ),
        );
        return {'success': false, 'message': message ?? '下载失败'};
      }
    } catch (e) {
      await _taskManager.updateTask(
        task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()),
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 恢复下载
  static Future<Map<String, dynamic>> resumeDownload(
    String taskId,
    String link,
    String savePath,
  ) async {
    try {
      await _taskManager.updateTask(
        _taskManager
                .getById(taskId)
                ?.copyWith(status: TaskStatus.downloading) ??
            DownloadTask(
              id: taskId,
              title: '恢复下载: $link',
              url: link,
              status: TaskStatus.downloading,
              source: 'xhs',
            ),
      );

      final resultStr = _python.callXhsBridge(
        'parse_link',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      await _taskManager.updateTask(
        _taskManager
                .getById(taskId)
                ?.copyWith(
                  title: title,
                  status: success ? TaskStatus.completed : TaskStatus.failed,
                  errorMessage: success
                      ? ''
                      : (result['message']?.toString() ?? ''),
                ) ??
            DownloadTask(
              id: taskId,
              title: title,
              url: link,
              status: success ? TaskStatus.completed : TaskStatus.failed,
              source: 'xhs',
            ),
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 检测链接信息（对应 xhs_bridge.detect_link_info）
  static Future<String> detectLinkInfo(String link) async {
    return _python.callXhsBridge('detect_link_info', jsonEncode([link]));
  }

  /// 批量下载用户作品（对应 xhs_bridge.batch_download_user）
  static Future<Map<String, dynamic>> batchDownloadUser(
    String userId,
    String nickname,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '下载用户作品: $nickname',
      url: 'user:$userId',
      status: TaskStatus.downloading,
      source: 'xhs',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callXhsBridge(
        'batch_download_user',
        jsonEncode([userId, nickname, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? nickname;

      await _taskManager.updateTask(
        task.copyWith(
          title: title,
          status: success ? TaskStatus.completed : TaskStatus.failed,
          errorMessage: success ? '' : (result['message']?.toString() ?? ''),
        ),
      );

      return result;
    } catch (e) {
      await _taskManager.updateTask(
        task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()),
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 批量下载专辑（对应 xhs_bridge.batch_download_collection）
  static Future<Map<String, dynamic>> batchDownloadCollection(
    String collectionId,
    String collectionName,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '下载专辑: $collectionName',
      url: 'collection:$collectionId',
      status: TaskStatus.downloading,
      source: 'xhs',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callXhsBridge(
        'batch_download_collection',
        jsonEncode([collectionId, collectionName, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? collectionName;

      await _taskManager.updateTask(
        task.copyWith(
          title: title,
          status: success ? TaskStatus.completed : TaskStatus.failed,
          errorMessage: success ? '' : (result['message']?.toString() ?? ''),
        ),
      );

      return result;
    } catch (e) {
      await _taskManager.updateTask(
        task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()),
      );
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 设置 Cookie（对应 xhs_bridge.set_cookie）
  static void setCookie(String cookie) {
    _python.callXhsBridge('set_cookie', jsonEncode([cookie]));
  }

  /// 暂停任务（对应 xhs_bridge.pause_task）
  static void pauseTask(String taskId) {
    _python.callXhsBridge('pause_task', jsonEncode([taskId]));
  }

  /// 恢复任务（对应 xhs_bridge.resume_task）
  static void resumeTask(String taskId) {
    _python.callXhsBridge('resume_task', jsonEncode([taskId]));
  }
}
