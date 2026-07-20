import 'package:flutter/material.dart';

/// 首页 - 完全复刻原项目 HomeScreen
/// 居中显示标题 + 两个平台选择按钮
class HomeScreen extends StatelessWidget {
  final VoidCallback onSelectDouyin;
  final VoidCallback onSelectXhs;

  const HomeScreen({
    super.key,
    required this.onSelectDouyin,
    required this.onSelectXhs,
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
              // 标题
              Text(
                '下载',
                style: textTheme.headlineLarge?.copyWith(color: scheme.primary),
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

              // 抖音按钮
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: onSelectDouyin,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('抖音', style: textTheme.titleMedium),
                ),
              ),
              const SizedBox(height: 12),

              // 小红书按钮
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: onSelectXhs,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('小红书', style: textTheme.titleMedium),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
