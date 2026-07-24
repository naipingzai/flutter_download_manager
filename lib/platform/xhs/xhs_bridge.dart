import '../bridge_base.dart';
import '../../service/native_download_service.dart';

/// 小红书下载桥接层
class XhsBridge {
  static final NativeDownloadService _native = NativeDownloadService.instance;

  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: (updateStatus) async {
        return await _native.downloadXhsNote(link, savePath,
            onStatus: updateStatus);
      },
    );
  }

  static void setCookie(String cookie) => _native.setXhsCookie(cookie);
  static void pauseTask(String taskId) {}
  static void resumeTask(String taskId) {}
}
