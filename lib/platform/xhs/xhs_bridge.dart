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
        updateStatus('🔍 解析小红书链接...');
        final result = await _native.downloadXhsNote(link, savePath);
        if (result['success'] == true) {
          updateStatus('✅ ${result['title'] ?? '下载完成'}');
        }
        return result;
      },
    );
  }

  static void setCookie(String cookie) => _native.setXhsCookie(cookie);
  static void pauseTask(String taskId) {}
  static void resumeTask(String taskId) {}
}
