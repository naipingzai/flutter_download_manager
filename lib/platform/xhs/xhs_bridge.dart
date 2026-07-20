import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_runner.dart';

/// 小红书下载桥接层 - 通过 PythonRunner 调用 xhs_bridge.py
class XhsBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonRunner _python = PythonRunner.instance;

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
      final resultStr = await _python.callXhsBridge(
        'parse_link',
        jsonEncode([link, savePath, taskId]),
      );
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

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
            errorMessage: result['message'] ?? '下载失败',
          ),
        );
        return {'success': false, 'message': result['message'] ?? '下载失败'};
      }
    } catch (e) {
      await _taskManager.updateTask(
        task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()),
      );
      return {'success': false, 'message': e.toString()};
    }
  }

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

      final resultStr = await _python.callXhsBridge(
        'parse_link',
        jsonEncode([link, savePath, taskId]),
      );
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      await _taskManager.updateTask(
        _taskManager.getById(taskId)?.copyWith(
                  title: title,
                  status: success ? TaskStatus.completed : TaskStatus.failed,
                  errorMessage:
                      success ? '' : (result['message']?.toString() ?? ''),
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

  static Future<String> detectLinkInfo(String link) async {
    return await _python.callXhsBridge(
      'detect_link_info',
      jsonEncode([link]),
    );
  }

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
      final resultStr = await _python.callXhsBridge(
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
      final resultStr = await _python.callXhsBridge(
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

  static void setCookie(String cookie) {
    _python.callXhsBridge('set_cookie', jsonEncode([cookie]));
  }

  static void pauseTask(String taskId) {
    _python.callXhsBridge('pause_task', jsonEncode([taskId]));
  }

  static void resumeTask(String taskId) {
    _python.callXhsBridge('resume_task', jsonEncode([taskId]));
  }
}
