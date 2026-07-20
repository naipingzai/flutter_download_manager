import 'platform_plugin.dart';

/// 插件注册中心。App 启动时注册所有平台插件。
class PluginRegistry {
  static final PluginRegistry _instance = PluginRegistry._internal();
  factory PluginRegistry() => _instance;
  PluginRegistry._internal();

  final List<PlatformPlugin> _plugins = [];

  void register(PlatformPlugin plugin) {
    _plugins.add(plugin);
  }

  List<PlatformPlugin> getAll() => List.unmodifiable(_plugins);

  PlatformPlugin? getById(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 根据 URL 匹配对应平台插件
  PlatformPlugin? matchLink(String url) {
    for (final plugin in _plugins) {
      for (final pattern in plugin.linkPatterns) {
        if (pattern.hasMatch(url)) {
          return plugin;
        }
      }
    }
    return null;
  }
}
