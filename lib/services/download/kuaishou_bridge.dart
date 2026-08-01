import 'bridge_base.dart';
import '../python/python_runner.dart';

/// 快手下载桥接层（通过 Python 脚本执行）
class KuaishouBridge {
  static final PythonRunner _python = PythonRunner.instance;

  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'kuaishou',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 调用 Python 解析快手链接...');
        try {
          final result = await _python.callPythonJson(
            module: 'ks_bridge',
            function: 'parse_link',
            args: [link, savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['title'] ?? '下载完成'}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': 'Python 调用失败: $e'};
        }
      },
    );
  }

  static Future<void> setCookie(String cookie) async {
    await _python.callPython(
        module: 'ks_bridge', function: 'set_cookie', args: [cookie]);
  }

  static Future<void> setProxy(String proxy) async {
    await _python.callPython(
        module: 'ks_bridge', function: 'set_proxy', args: [proxy]);
  }
}
