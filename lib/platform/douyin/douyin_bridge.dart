import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../bridge_base.dart';
import '../../service/python_service.dart';

/// 抖音下载桥接层
/// Python C++ 桥接优先，纯 Dart 引擎作为全平台回退 (iOS/macOS 等)
class DouyinBridge {
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
        // 纯 Dart 回退
        return await BridgeBase.native.downloadDouyinVideo(link, savePath);
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

  /// 检测链接信息
  static String detectLinkInfo(String link) {
    if (BridgeBase.usePython) {
      final result = BridgeBase.callPython(
        'dy_bridge',
        'detect_link_info',
        [link],
      );
      return jsonEncode(result);
    }
    return jsonEncode({
      'success': true,
      'message': '原生模式：请直接粘贴链接下载',
    });
  }

  /// 录制直播
  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    if (BridgeBase.usePython) {
      return BridgeBase.callPython(
        'dy_bridge',
        'record_live',
        [liveUrl, savePath, ''],
      );
    }
    return {'success': false, 'message': '直播录制需要 Python 环境'};
  }

  /// 采集评论
  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    if (BridgeBase.usePython) {
      return BridgeBase.callPython(
        'dy_bridge',
        'scrape_comments',
        [link, savePath, ''],
      );
    }
    return {'success': false, 'message': '评论采集需要 Python 环境'};
  }

  /// 获取数据统计
  static String getDataStats(String link) {
    if (BridgeBase.usePython) {
      final result = BridgeBase.callPython(
        'dy_bridge',
        'get_data_stats',
        [link],
      );
      return jsonEncode(result);
    }
    return jsonEncode({'success': false, 'message': '数据统计需要 Python 环境'});
  }

  /// 设置 Cookie
  static void setCookie(String cookie) {
    BridgeBase.native.setDouyinCookie(cookie);
    if (BridgeBase.usePython) {
      PythonService.instance.saveCookie('douyin', cookie);
      BridgeBase.callPython('dy_bridge', 'set_cookie', [cookie]);
    }
  }

  /// 暂停任务
  static void pauseTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('dy_bridge', 'pause_task', [taskId]);
    }
  }

  /// 恢复任务
  static void resumeTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('dy_bridge', 'resume_task', [taskId]);
    }
  }
}
