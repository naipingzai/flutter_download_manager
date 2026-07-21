import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../bridge_base.dart';
import '../../service/http_download_service.dart';
import '../../service/python_service.dart';

/// 抖音下载桥接层
/// 优先使用 Python (Linux/Android)，Python 不可用时回退到纯 Dart HTTP (iOS/macOS)
class DouyinBridge {
  static final HttpDownloadService _http = HttpDownloadService.instance;

  /// 解析抖音链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: () async {
        if (BridgeBase.usePython) {
          final result = BridgeBase.callPython(
            'dy_bridge',
            'parse_link',
            [link, savePath, ''],
          );
          if (result['success'] == true) {
            final path = result['path']?.toString() ?? '';
            final filePath = await _findDownloadedFile(path, savePath);
            if (filePath != null) {
              final file = File(filePath);
              if (await file.exists()) result['path'] = filePath;
            }
          }
          return result;
        }
        final result = await _http.downloadDouyinVideo(link, savePath);
        if (result['success'] == true) {
          final filePath = await _findDownloadedFile(
            result['path']?.toString() ?? '',
            savePath,
          );
          if (filePath != null) result['path'] = filePath;
        }
        return result;
      },
    );
  }

  static Future<String?> _findDownloadedFile(
      String filePath, String savePath) async {
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) return filePath;
    }
    try {
      final dir = Directory(savePath);
      if (await dir.exists()) {
        final files = await dir.list().where((e) => e is File).toList();
        if (files.isNotEmpty) {
          files.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
          return files.first.path;
        }
      }
    } catch (_) {}
    return null;
  }

  static String detectLinkInfo(String link) {
    if (BridgeBase.usePython) {
      final result = BridgeBase.callPython(
        'dy_bridge',
        'detect_link_info',
        [link],
      );
      return jsonEncode(result);
    }
    return BridgeBase.httpModeMessage('链接检测');
  }

  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    if (!BridgeBase.usePython) {
      return BridgeBase.pythonRequiredResult('直播录制');
    }
    return BridgeBase.callPython(
      'dy_bridge',
      'record_live',
      [liveUrl, savePath, ''],
    );
  }

  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    if (!BridgeBase.usePython) {
      return BridgeBase.pythonRequiredResult('评论采集');
    }
    return BridgeBase.callPython(
      'dy_bridge',
      'scrape_comments',
      [link, savePath, ''],
    );
  }

  static String getDataStats(String link) {
    if (BridgeBase.usePython) {
      final result = BridgeBase.callPython(
        'dy_bridge',
        'get_data_stats',
        [link],
      );
      return jsonEncode(result);
    }
    return jsonEncode(BridgeBase.pythonRequiredResult('数据统计'));
  }

  static void setCookie(String cookie) {
    _http.setDouyinCookie(cookie);
    if (BridgeBase.usePython) {
      PythonService.instance.saveCookie('douyin', cookie);
      BridgeBase.callPython('dy_bridge', 'set_cookie', [cookie]);
    }
  }

  static void pauseTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('dy_bridge', 'pause_task', [taskId]);
    }
  }

  static void resumeTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('dy_bridge', 'resume_task', [taskId]);
    }
  }
}
