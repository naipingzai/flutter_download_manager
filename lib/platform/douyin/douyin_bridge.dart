import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_service.dart';

/// 抖音下载桥接层，对应原项目 DyPythonBridge
/// 通过 C++ 嵌入的 CPython 解释器调用原始 dy_bridge.py 脚本
class DouyinBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;

  /// 解析链接并下载（对应 dy_bridge.parse_link）
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
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      // 调用 Python dy_bridge.parse_link(link, save_path, task_id)
      final resultStr = _python.callDyBridge(
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
              source: 'douyin',
            ),
      );

      // 调用 Python
      final resultStr = _python.callDyBridge(
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
              source: 'douyin',
            ),
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 获取收藏夹列表（对应 dy_bridge.list_collect_folders）
  static Future<String> listCollectFolders() async {
    return _python.callDyBridge('list_collect_folders', '[]');
  }

  /// 批量下载收藏夹（对应 dy_bridge.batch_download_collect）
  static Future<Map<String, dynamic>> batchDownloadCollect(
    String collectId,
    String collectName,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '下载收藏夹: $collectName',
      url: 'collect:$collectId',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'batch_download_collect',
        jsonEncode([collectId, collectName, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? collectName;

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

  /// 检测链接信息（对应 dy_bridge.detect_link_info）
  static Future<String> detectLinkInfo(String link) async {
    return _python.callDyBridge('detect_link_info', jsonEncode([link]));
  }

  /// 批量下载账号作品（对应 dy_bridge.batch_download_account）
  static Future<Map<String, dynamic>> batchDownloadAccount(
    String secUid,
    String nickname,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '下载账号作品: $nickname',
      url: 'account:$secUid',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'batch_download_account',
        jsonEncode([secUid, nickname, savePath, taskId]),
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

  /// 批量下载合集作品（对应 dy_bridge.batch_download_mix）
  static Future<Map<String, dynamic>> batchDownloadMix(
    String mixId,
    String mixName,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '下载合集: $mixName',
      url: 'mix:$mixId',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'batch_download_mix',
        jsonEncode([mixId, mixName, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? mixName;

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

  /// 录制直播（对应 dy_bridge.record_live）
  static Future<Map<String, dynamic>> recordLive(
    String liveUrl,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '直播录制: $liveUrl',
      url: liveUrl,
      type: 'live',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'record_live',
        jsonEncode([liveUrl, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? liveUrl;

      await _taskManager.updateTask(
        task.copyWith(
          title: '直播录制: $title',
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

  /// 评论采集（对应 dy_bridge.scrape_comments）
  static Future<Map<String, dynamic>> scrapeComments(
    String link,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '评论采集: $link',
      url: link,
      type: 'comments',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'scrape_comments',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;

      await _taskManager.updateTask(
        task.copyWith(
          title: '评论采集: $title',
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

  /// 下载封面（对应 dy_bridge.download_cover）
  static Future<Map<String, dynamic>> downloadCover(
    String link,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '封面下载: $link',
      url: link,
      type: 'cover',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'download_cover',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;

      await _taskManager.updateTask(
        task.copyWith(
          title: '封面: ${result['title'] ?? link}',
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

  /// 音频提取（对应 dy_bridge.extract_audio）
  static Future<Map<String, dynamic>> extractAudio(
    String link,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '音频提取: $link',
      url: link,
      type: 'audio',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'extract_audio',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;

      await _taskManager.updateTask(
        task.copyWith(
          title: '音频: ${result['title'] ?? link}',
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

  /// 动图下载（对应 dy_bridge.download_livephoto）
  static Future<Map<String, dynamic>> downloadLivephoto(
    String link,
    String savePath,
  ) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
      id: taskId,
      title: '动图下载: $link',
      url: link,
      type: 'livephoto',
      status: TaskStatus.downloading,
      source: 'douyin',
    );
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
        'download_livephoto',
        jsonEncode([link, savePath, taskId]),
      );

      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;

      await _taskManager.updateTask(
        task.copyWith(
          title: '动图: ${result['title'] ?? link}',
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

  /// 获取数据统计（对应 dy_bridge.get_data_stats）
  static Future<String> getDataStats(String link) async {
    return _python.callDyBridge('get_data_stats', jsonEncode([link]));
  }

  /// 设置 Cookie（对应 dy_bridge.set_cookie）
  static void setCookie(String cookie) {
    _python.callDyBridge('set_cookie', jsonEncode([cookie]));
  }

  /// 暂停任务（对应 dy_bridge.pause_task）
  static void pauseTask(String taskId) {
    _python.callDyBridge('pause_task', jsonEncode([taskId]));
  }

  /// 恢复任务（对应 dy_bridge.resume_task）
  static void resumeTask(String taskId) {
    _python.callDyBridge('resume_task', jsonEncode([taskId]));
  }

  /// 获取用户作品列表（对应 dy_bridge.list_account_works）
  static Future<String> listAccountWorks(String secUid) async {
    return _python.callDyBridge('list_account_works', jsonEncode([secUid]));
  }

  /// 重新下载历史记录（对应 dy_bridge.redownload_from_history）
  static Future<Map<String, dynamic>> redownloadFromHistory(
    String savePath,
  ) async {
    try {
      final resultStr = _python.callDyBridge(
        'redownload_from_history',
        jsonEncode([savePath]),
      );
      return jsonDecode(resultStr) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
