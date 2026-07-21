import 'dart:async';
import 'dart:convert';
import '../bridge_base.dart';
import '../../service/native_download_service.dart';

/// 小红书下载桥接层 — 全平台统一调用 NativeDownloadService
class XhsBridge {
  static final NativeDownloadService _native = NativeDownloadService.instance;

  /// 解析小红书链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: () async => await _native.downloadXhsNote(link, savePath),
    );
  }

  /// 检测笔记信息
  static String detectLinkInfo(String link) =>
      jsonEncode({'success': true, 'message': '请直接粘贴链接下载'});

  /// 设置 Cookie
  static void setCookie(String cookie) => _native.setXhsCookie(cookie);

  /// 暂停任务
  static void pauseTask(String taskId) {}

  /// 恢复任务
  static void resumeTask(String taskId) {}
}
