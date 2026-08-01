import 'bridge_base.dart';
import '../python/python_runner.dart';

/// 抖音下载桥接层（通过内嵌 Python 脚本执行）
/// 暴露 dy_bridge.py 的所有功能
class DouyinBridge {
  static final PythonRunner _python = PythonRunner.instance;

  /// 解析链接并下载单个作品
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 调用 Python 解析抖音链接...');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
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

  /// 检测链接信息（提取作者/合集信息）
  static Future<Map<String, dynamic>> detectLinkInfo(String link) async {
    try {
      final result = await _python.callPythonJson(
        module: 'dy_bridge',
        function: 'detect_link_info',
        args: [link],
      );
      return result;
    } catch (e) {
      return {'success': false, 'message': '检测失败: $e'};
    }
  }

  /// 批量下载作者作品
  static Future<Map<String, dynamic>> batchDownloadAccount(
      String secUid, String nickname, String savePath) async {
    return BridgeBase.executeTask(
      link: 'account:$secUid',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 批量下载作者作品: $nickname');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
            function: 'batch_download_account',
            args: [secUid, nickname, savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['title']} - ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '批量下载失败: $e'};
        }
      },
    );
  }

  /// 列出作者作品列表（不下载）
  static Future<Map<String, dynamic>> listAccountWorks(String secUid) async {
    try {
      final result = await _python.callPythonJson(
        module: 'dy_bridge',
        function: 'list_account_works',
        args: [secUid],
      );
      return result;
    } catch (e) {
      return {'success': false, 'message': '获取作品列表失败: $e'};
    }
  }

  /// 获取收藏夹列表
  static Future<Map<String, dynamic>> listCollectFolders() async {
    try {
      final result = await _python.callPythonJson(
        module: 'dy_bridge',
        function: 'list_collect_folders',
        args: [],
      );
      return result;
    } catch (e) {
      return {'success': false, 'message': '获取收藏夹失败: $e'};
    }
  }

  /// 批量下载收藏夹
  static Future<Map<String, dynamic>> batchDownloadCollect(
      String collectId, String collectName, String savePath) async {
    return BridgeBase.executeTask(
      link: 'collect:$collectId',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 下载收藏夹: $collectName');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
            function: 'batch_download_collect',
            args: [collectId, collectName, savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '收藏夹下载失败: $e'};
        }
      },
    );
  }

  /// 批量下载合集
  static Future<Map<String, dynamic>> batchDownloadMix(
      String mixId, String mixName, String savePath) async {
    return BridgeBase.executeTask(
      link: 'mix:$mixId',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 下载合集: $mixName');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
            function: 'batch_download_mix',
            args: [mixId, mixName, savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '合集下载失败: $e'};
        }
      },
    );
  }

  /// 从历史记录重新下载
  static Future<Map<String, dynamic>> redownloadFromHistory(
      String savePath) async {
    return BridgeBase.executeTask(
      link: 'history:redownload',
      savePath: savePath,
      source: 'douyin',
      type: 'video',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 从历史记录重新下载...');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
            function: 'redownload_from_history',
            args: [savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '重新下载失败: $e'};
        }
      },
    );
  }

  /// 录制直播
  static Future<Map<String, dynamic>> recordLive(
      String liveUrl, String savePath) async {
    return BridgeBase.executeTask(
      link: 'live:$liveUrl',
      savePath: savePath,
      source: 'douyin',
      type: 'live',
      execute: (updateStatus, updateProgress) async {
        updateStatus('🐍 开始录制直播...');
        try {
          final result = await _python.callPythonJson(
            module: 'dy_bridge',
            function: 'record_live',
            args: [liveUrl, savePath, ''],
          );
          if (result['success'] == true) {
            updateStatus('✅ ${result['message']}');
          }
          return result;
        } catch (e) {
          return {'success': false, 'message': '直播录制失败: $e'};
        }
      },
    );
  }

  /// 获取 Python 配置
  static Future<Map<String, dynamic>> getConfig() async {
    try {
      final result = await _python.callPythonJson(
        module: 'dy_bridge',
        function: 'get_config',
        args: [],
      );
      return result;
    } catch (e) {
      return {'success': false, 'message': '获取配置失败: $e'};
    }
  }

  /// 更新 Python 配置
  static Future<Map<String, dynamic>> updateConfig(String configJson) async {
    try {
      final result = await _python.callPythonJson(
        module: 'dy_bridge',
        function: 'update_config',
        args: [configJson],
      );
      return result;
    } catch (e) {
      return {'success': false, 'message': '更新配置失败: $e'};
    }
  }

  /// 设置 Cookie
  static Future<void> setCookie(String cookie) async {
    await _python.setDouyinCookie(cookie);
  }

  /// 设置代理
  static Future<void> setProxy(String proxy) async {
    await _python.setDouyinProxy(proxy);
  }
}
