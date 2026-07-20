/// 平台插件接口。每个平台（抖音、小红书等）实现此接口，
/// 向框架提供元信息和链接匹配规则。
abstract class PlatformPlugin {
  /// 唯一标识
  String get id;

  /// 显示名称
  String get displayName;

  /// 该平台支持的链接正则
  List<RegExp> get linkPatterns;

  /// 收到分享链接时回调
  void onSharedLink(String link);
}
