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
      execute: (updateStatus) async {
        return await _native.downloadDouyinVideo(link, savePath,
            onStatus: updateStatus);
      },
    );
  }

  static void setCookie(String cookie) => _native.setDouyinCookie(cookie);
  static void pauseTask(String taskId) {}
  static void resumeTask(String taskId) {}
}
