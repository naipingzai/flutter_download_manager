import 'dart:io';
import '../bridge_base.dart';
import '../../service/native_download_service.dart';

/// 抖音下载桥接层
class DouyinBridge {
  static final NativeDownloadService _native = NativeDownloadService.instance;

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
          if (path.isNotEmpty) {
            final file = File(path);
            if (await file.exists()) return result;
          }
        }
        return result;
      },
    );
  }

  static void setCookie(String cookie) => _native.setDouyinCookie(cookie);
  static void pauseTask(String taskId) {}
  static void resumeTask(String taskId) {}
}
