import 'dart:async';
import 'dart:convert';
import '../bridge_base.dart';
import '../../service/python_service.dart';

/// 小红书下载桥接层
/// Python C++ 桥接优先，纯 Dart 引擎作为全平台回退 (iOS/macOS 等)
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
        if (BridgeBase.usePython) {
          return BridgeBase.callPython(
            'xhs_bridge',
            'parse_link',
            [link, savePath, ''],
          );
        }
        // 纯 Dart 回退
        return await BridgeBase.native.downloadXhsNote(link, savePath);
      },
    );
  }

  /// 检测笔记信息
  static String detectLinkInfo(String link) {
    if (BridgeBase.usePython) {
      final result = BridgeBase.callPython(
        'xhs_bridge',
        'detect_note_info',
        [link],
      );
      return jsonEncode(result);
    }
    return jsonEncode({
      'success': true,
      'message': '原生模式：请直接粘贴链接下载',
    });
  }

  /// 设置 Cookie
  static void setCookie(String cookie) {
    BridgeBase.native.setXhsCookie(cookie);
    if (BridgeBase.usePython) {
      PythonService.instance.saveCookie('xhs', cookie);
      BridgeBase.callPython('xhs_bridge', 'set_cookie', [cookie]);
    }
  }

  /// 暂停任务
  static void pauseTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('xhs_bridge', 'pause_task', [taskId]);
    }
  }

  /// 恢复任务
  static void resumeTask(String taskId) {
    if (BridgeBase.usePython) {
      BridgeBase.callPython('xhs_bridge', 'resume_task', [taskId]);
    }
  }
}
