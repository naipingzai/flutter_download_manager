import 'dart:async';
import 'dart:convert';
import '../bridge_base.dart';
import '../../service/python_service.dart';

/// 小红书下载桥接层 - 纯 Python 实现
class XhsBridge {
  /// 解析小红书链接并下载
  static Future<Map<String, dynamic>> parseAndDownload(
      String link, String savePath) async {
    return BridgeBase.executeTask(
      link: link,
      savePath: savePath,
      source: 'xhs',
      type: 'note',
      execute: () async {
        return BridgeBase.callPython(
          'xhs_bridge',
          'parse_link',
          [link, savePath, ''],
        );
      },
    );
  }

  /// 检测笔记信息
  static String detectLinkInfo(String link) {
    final result = BridgeBase.callPython(
      'xhs_bridge',
      'detect_note_info',
      [link],
    );
    return jsonEncode(result);
  }

  /// 设置 Cookie
  static void setCookie(String cookie) {
    PythonService.instance.saveCookie('xhs', cookie);
    BridgeBase.callPython('xhs_bridge', 'set_cookie', [cookie]);
  }

  /// 暂停任务
  static void pauseTask(String taskId) {
    BridgeBase.callPython('xhs_bridge', 'pause_task', [taskId]);
  }

  /// 恢复任务
  static void resumeTask(String taskId) {
    BridgeBase.callPython('xhs_bridge', 'resume_task', [taskId]);
  }
}
