import 'package:flutter/material.dart';

/// 首页 — 平台选择
/// 三个平台卡片: 抖音 / 小红书 / 快手
class HomeScreen extends StatelessWidget {
  final VoidCallback onSelectDouyin;
  final VoidCallback onSelectXhs;
  final VoidCallback? onSelectKuaishou;

  const HomeScreen({
    super.key,
    required this.onSelectDouyin,
    required this.onSelectXhs,
    this.onSelectKuaishou,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题区域
              Icon(
                Icons.cloud_download_rounded,
                size: 64,
                color: scheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '高级下载器',
                style: textTheme.headlineLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '聚合多平台内容下载工具',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // 抖音卡片
              _PlatformCard(
                title: '抖音',
                subtitle: '下载视频、图集、直播',
                icon: Icons.music_note_rounded,
                color: const Color(0xFFFE2C55),
                onTap: onSelectDouyin,
              ),
              const SizedBox(height: 12),

              // 小红书卡片
              _PlatformCard(
                title: '小红书',
                subtitle: '下载笔记、图片、视频',
                icon: Icons.menu_book_rounded,
                color: const Color(0xFFFF2442),
                onTap: onSelectXhs,
              ),
              const SizedBox(height: 12),

              // 快手卡片
              _PlatformCard(
                title: '快手',
                subtitle: '下载视频、图集、直播',
                icon: Icons.videocam_rounded,
                color: const Color(0xFFFF6600),
                onTap: onSelectKuaishou ?? () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 平台选择卡片
class _PlatformCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PlatformCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
