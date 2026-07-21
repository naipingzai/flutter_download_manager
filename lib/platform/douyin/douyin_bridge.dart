import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../model/download_task.dart';
import '../../service/download_task_manager.dart';
import '../../service/python_service.dart';

/// 抖音下载桥接层 - 通过 PythonService FFI 调用 dy_bridge.py
class DouyinBridge {
  static const _uuid = Uuid();
  static final DownloadTaskManager _taskManager = DownloadTaskManager();
  static final PythonService _python = PythonService.instance;

  /// 解析抖音链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
        id: taskId,
        title: '解析中: $link',
        url: link,
        status: TaskStatus.downloading,
        source: 'douyin');
    await _taskManager.addTask(task);

    try {
      final resultStr = _python.callDyBridge(
          'parse_link', jsonEncode([link, savePath, taskId]));
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;
      final filePath = result['path']?.toString() ?? '';

      int fileSize = 0;
      if (filePath.isNotEmpty) {
        try {
          final file = File(filePath);
          if (await file.exists()) fileSize = await file.length();
        } catch (_) {}
      }

      String actualPath = filePath;
      int actualSize = fileSize;
      if (actualPath.isEmpty || actualSize == 0) {
        try {
          final dir = Directory(savePath);
          if (await dir.exists()) {
            final files = await dir.list().where((e) => e is File).toList();
            if (files.isNotEmpty) {
              files.sort((a, b) =>
                  b.statSync().modified.compareTo(a.statSync().modified));
              actualPath = files.first.path;
              actualSize = files.first.statSync().size;
            }
          }
        } catch (_) {}
      }

      if (success) {
        await _taskManager.updateTask(task.copyWith(
            title: title,
            status: TaskStatus.completed,
            filePath: actualPath,
            downloadedSize: actualSize,
            totalSize: actualSize));
        return {'success': true, 'title': title, 'path': actualPath};
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

  /// 检测链接信息（视频/图集/直播）
  static Future<String> detectLinkInfo(String link) async =>
      _python.callDyBridge('detect_link_info', jsonEncode([link]));

  /// 录制直播
  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
        id: taskId,
        title: '直播录制: $liveUrl',
        url: liveUrl,
        type: 'live',
        status: TaskStatus.downloading,
        source: 'douyin');
    await _taskManager.addTask(task);
    try {
      final resultStr = _python.callDyBridge(
          'record_live', jsonEncode([liveUrl, savePath, taskId]));
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? liveUrl;
      await _taskManager.updateTask(task.copyWith(
          title: '直播录制: $title',
          status: success ? TaskStatus.completed : TaskStatus.failed,
          errorMessage: success ? '' : (result['message']?.toString() ?? '')));
      return result;
    } catch (e) {
      await _taskManager.updateTask(
          task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 采集评论
  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    final taskId = _uuid.v4();
    final task = DownloadTask(
        id: taskId,
        title: '评论采集: $link',
        url: link,
        type: 'comments',
        status: TaskStatus.downloading,
        source: 'douyin');
    await _taskManager.addTask(task);
    try {
      final resultStr = _python.callDyBridge(
          'scrape_comments', jsonEncode([link, savePath, taskId]));
      final result = jsonDecode(resultStr) as Map<String, dynamic>;
      final success = result['success'] == true;
      final title = result['title']?.toString() ?? link;
      await _taskManager.updateTask(task.copyWith(
          title: '评论采集: $title',
          status: success ? TaskStatus.completed : TaskStatus.failed,
          errorMessage: success ? '' : (result['message']?.toString() ?? '')));
      return result;
    } catch (e) {
      await _taskManager.updateTask(
          task.copyWith(status: TaskStatus.failed, errorMessage: e.toString()));
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 获取数据统计
  static Future<String> getDataStats(String link) async =>
      _python.callDyBridge('get_data_stats', jsonEncode([link]));

  /// 设置 Cookie
  static void setCookie(String cookie) {
    _python.saveCookie('douyin', cookie);
    _python.callDyBridge('set_cookie', jsonEncode([cookie]));
  }

  /// 暂停任务
  static void pauseTask(String taskId) =>
      _python.callDyBridge('pause_task', jsonEncode([taskId]));

  /// 恢复任务
  static void resumeTask(String taskId) =>
      _python.callDyBridge('resume_task', jsonEncode([taskId]));
}
