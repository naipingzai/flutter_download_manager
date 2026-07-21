import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../bridge_base.dart';
import '../../service/native_download_service.dart';

/// 抖音下载桥接层 — 全平台统一调用 NativeDownloadService
class DouyinBridge {
  static final NativeDownloadService _native = NativeDownloadService.instance;

  /// 解析抖音链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: () async {
        final result = await _native.downloadDouyinVideo(link, savePath);
        if (result['success'] == true) {
          final path = result['path']?.toString() ?? '';
          final filePath = await _findDownloadedFile(path, savePath);
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) result['path'] = filePath;
          }
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

  /// 检测链接信息
  static String detectLinkInfo(String link) =>
      jsonEncode({'success': true, 'message': '请直接粘贴链接下载'});

  /// 录制直播
  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    return {'success': false, 'message': '直播录制功能暂未实现'};
  }

  /// 采集评论
  static Future<Map<String, dynamic>> scrapeComments(
      String link, String savePath) async {
    return {'success': false, 'message': '评论采集功能暂未实现'};
  }

  /// 获取数据统计
  static String getDataStats(String link) =>
      jsonEncode({'success': false, 'message': '数据统计功能暂未实现'});

  /// 设置 Cookie
  static void setCookie(String cookie) => _native.setDouyinCookie(cookie);

  /// 暂停任务
  static void pauseTask(String taskId) {}

  /// 恢复任务
  static void resumeTask(String taskId) {}
}
