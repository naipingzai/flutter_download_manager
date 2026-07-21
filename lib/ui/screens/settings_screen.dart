import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../service/cookie_store.dart';

/// 设置页面 - 完全复刻原项目 ProfileScreen
/// Cookie 管理 + 关于信息
class SettingsScreen extends StatefulWidget {
  final String platform;
  final VoidCallback? onCookie;

  const SettingsScreen({super.key, this.platform = '', this.onCookie});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cookieStatus = '未设置';
  final String _versionName = '1.0.0';

  String get _platformName => widget.platform == 'xhs' ? '小红书' : '抖音';

  @override
  void initState() {
    super.initState();
    _loadCookieStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCookieStatus();
  }

  Future<void> _loadCookieStatus() async {
    final store = CookieStore(platform: widget.platform);
    await store.load();
    final activeCookie = store.getActiveCookie();
    if (mounted) {
      setState(() {
        if (activeCookie != null && activeCookie.isNotEmpty) {
          final keyCount =
              activeCookie.split(';').where((s) => s.contains('=')).length;
          _cookieStatus = '使用: ${store.getActiveName()} ($keyCount 个字段)';
        } else {
          _cookieStatus = '未设置';
        }
      });
    }
  }

  void _handleCookieTap() {
    if (widget.onCookie != null) {
      widget.onCookie!();
    }
  }

  // Cookie 对话框已移至 CookieManageScreen

  /// 清理下载缓存（应用文档目录中的下载文件）
  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将删除应用中保存的所有下载文件（不影响已保存到相册的内容）。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dirs = ['DyDownload', 'XhsDownload'];
      int deletedCount = 0;
      for (final dirName in dirs) {
        final dir = Directory('${appDir.path}/$dirName');
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              await entity.delete();
              deletedCount++;
            }
          }
          await dir.delete(recursive: true);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清理 $deletedCount 个文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于'),
        content: const Text(
          '高级下载器 (AdvanceDownloader) — 聚合多平台内容下载工具\n\n'
          '作者: 奶瓶仔\n'
          '开源协议: GPL-3.0\n\n'
          '抖音模块基于 TikTokDownloader by JoeanAmier\n'
          'https://github.com/JoeanAmier/TikTokDownloader\n\n'
          '小红书模块基于 XHS-Downloader by JoeanAmier\n'
          'https://github.com/JoeanAmier/XHS-Downloader',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 平台设置标题 ──
          Text(
            '$_platformName设置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),

          // Cookie 管理行 - 对应原项目 SettingsRow
          _SettingsRow(
            title: 'Cookie 管理',
            subtitle: _cookieStatus,
            onTap: _handleCookieTap,
          ),

          const SizedBox(height: 8),

          // 缓存管理行
          _SettingsRow(
            title: '清理缓存',
            subtitle: '删除下载的临时文件',
            onTap: _clearCache,
          ),

          const SizedBox(height: 24),

          // ── 关于标题 ──
          Text(
            '关于',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),

          // 关于卡片 - 对应原项目关于 Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: _showAboutDialog,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '高级下载器',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            '聚合多平台内容下载工具',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'v$_versionName',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置行 - 对应原项目 SettingsRow
class _SettingsRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
