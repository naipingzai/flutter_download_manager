import '../../framework/platform_plugin.dart';

/// 抖音平台插件实现，对应原项目 DouyinPlugin
class DouyinPlugin extends PlatformPlugin {
  @override
  String get id => 'douyin';

  @override
  String get displayName => '抖音';

  @override
  List<RegExp> get linkPatterns => [
    RegExp(r'https?://[^\s]*?douyin\.com[^\s]*', caseSensitive: false),
    RegExp(r'https?://[^\s]*?tiktok\.com[^\s]*', caseSensitive: false),
    RegExp(r'https?://[^\s]*?iesdouyin\.com[^\s]*', caseSensitive: false),
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
