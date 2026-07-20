import '../../framework/platform_plugin.dart';

/// 小红书平台插件实现，对应原项目 XhsPlugin
class XhsPlugin extends PlatformPlugin {
  @override
  String get id => 'xhs';

  @override
  String get displayName => '小红书';

  @override
  List<RegExp> get linkPatterns => [
    RegExp(r'https?://[^\s]*?xiaohongshu\.com[^\s]*', caseSensitive: false),
    RegExp(r'https?://[^\s]*?xhslink\.com[^\s]*', caseSensitive: false),
    RegExp(r'https?://[^\s]*?xhs\.com[^\s]*', caseSensitive: false),
  ];

  Function(String)? _sharedLinkCallback;

  @override
  void onSharedLink(String link) {
    _sharedLinkCallback?.call(link);
  }

  void setSharedLinkCallback(Function(String) callback) {
    _sharedLinkCallback = callback;
  }
}
