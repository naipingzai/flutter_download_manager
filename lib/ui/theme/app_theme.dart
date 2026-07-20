import 'package:flutter/material.dart';

/// 应用主题配置，对应原项目 AppTheme
/// Material 3 动态取色主题
class AppTheme {
  static ThemeData lightTheme(ColorScheme? colorScheme) {
    final scheme =
        colorScheme ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        );

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

  static ThemeData darkTheme(ColorScheme? colorScheme) {
    final scheme =
        colorScheme ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        );

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

  /// 任务状态颜色
  static Color statusColor(TaskStatusColors status, ColorScheme scheme) {
    switch (status) {
      case TaskStatusColors.queued:
        return scheme.outline;
      case TaskStatusColors.downloading:
        return scheme.primary;
      case TaskStatusColors.paused:
        return scheme.tertiary;
      case TaskStatusColors.completed:
        return Colors.green;
      case TaskStatusColors.failed:
        return scheme.error;
    }
  }
}

enum TaskStatusColors { queued, downloading, paused, completed, failed }
