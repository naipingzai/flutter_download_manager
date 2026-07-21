/// 兼容性存根 — 原 FFI 集成已移除，所有平台统一使用 NativeDownloadService。
/// 保留类名仅用于兼容历史调用代码。
class PythonService {
  static final PythonService instance = PythonService._();
  PythonService._();

  /// 始终返回 true，业务调用直接走 NativeDownloadService
  bool get isReady => true;

  String get version => 'native';

  /// 兼容接口：直接返回错误，不再使用 Python
  String callDyBridge(String functionName, String argsJson) =>
      '{"success":false,"message":"已迁移至 NativeDownloadService"}';

  String callXhsBridge(String functionName, String argsJson) =>
      '{"success":false,"message":"已迁移至 NativeDownloadService"}';

  Future<void> init({String? scriptDir}) async {}
  Future<void> saveCookie(String platform, String cookie) async {}
  void destroy() {}
}
