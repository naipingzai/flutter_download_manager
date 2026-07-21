import 'package:flutter/material.dart';
import '../../model/download_task.dart';

/// 应用主题配置，Material 3 动态取色主题
class AppTheme {
  static const _seedColor = Color(0xFF6750A4);

  static ThemeData lightTheme(ColorScheme? colorScheme) =>
      _buildTheme(colorScheme, Brightness.light);

  static ThemeData darkTheme(ColorScheme? colorScheme) =>
      _buildTheme(colorScheme, Brightness.dark);

  static ThemeData _buildTheme(
      ColorScheme? colorScheme, Brightness brightness) {
    final scheme = colorScheme ??
        ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
    );
  }

  /// 根据任务状态返回对应颜色
  static Color statusColor(TaskStatus status, ColorScheme scheme) {
    switch (status) {
      case TaskStatus.queued:
        return scheme.outline;
      case TaskStatus.downloading:
        return scheme.primary;
      case TaskStatus.paused:
        return scheme.tertiary;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.failed:
        return scheme.error;
    }
  }
}
