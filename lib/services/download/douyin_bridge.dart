import 'bridge_base.dart';
import 'native_download_service.dart';

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
      execute: (updateStatus, updateProgress) async {
        return await _native.downloadDouyinVideo(link, savePath,
            onStatus: updateStatus, onProgress: updateProgress);
      },
    );
  }

  static void setCookie(String cookie) => _native.setDouyinCookie(cookie);
}
