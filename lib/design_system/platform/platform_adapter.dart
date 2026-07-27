import 'dart:io' as io;

/// 平台枚举
enum AppPlatform { ios, android, other }

/// Platform Adapter — Design System 集中平台判断
///
/// 业务代码禁止直接使用 io.Platform.isIOS / isAndroid / isLinux
/// 所有平台判断必须通过本文件暴露的 API。
class PlatformAdapter {
  static final AppPlatform _current = _detect();

  /// 当前平台
  static AppPlatform get current => _current;

  static bool get isIOS => _current == AppPlatform.ios;
  static bool get isAndroid => _current == AppPlatform.android;

  /// 启动时调用一次
  static void init() {}

  static AppPlatform _detect() {
    try {
      if (io.Platform.isIOS) return AppPlatform.ios;
      if (io.Platform.isAndroid) return AppPlatform.android;
    } catch (_) {
      return AppPlatform.other;
    }
    return AppPlatform.other;
  }
}
