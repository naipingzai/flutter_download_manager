/// 平台标识常量，避免字符串硬编码
class PlatformConstants {
  PlatformConstants._();

  static const String douyin = 'douyin';
  static const String xhs = 'xhs';

  /// 平台显示名称映射
  static const Map<String, String> displayNames = {
    douyin: '抖音',
    xhs: '小红书',
  };

  /// 下载目录名
  static const Map<String, String> downloadDirs = {
    douyin: 'DyDownload',
    xhs: 'XhsDownload',
  };
}
