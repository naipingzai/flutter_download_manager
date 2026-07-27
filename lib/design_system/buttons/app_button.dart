import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../platform/platform_adapter.dart';

/// 按钮语义变体 — 业务代码只声明意图
enum AppButtonVariant {
  primary, // 主操作（填充背景）
  secondary, // 次要操作（描边）
  text, // 文字按钮
  destructive, // 危险/删除操作
}

/// 按钮尺寸
enum AppButtonSize { small, medium, large }

/// AppButton — Design System 按钮
///
/// 业务代码：
/// ```
/// AppButton(label: '删除', variant: AppButtonVariant.destructive, onPressed: delete);
/// ```
///
/// 平台适配：
/// - iOS → CupertinoButton
/// - Android → Material FilledButton / OutlinedButton / TextButton
///
/// 业务层不得知道实际实现。
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool expand;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.expand = false,
    this.loading = false,
  });

  double get _minHeight => switch (size) {
        AppButtonSize.small => 36.0,
        AppButtonSize.medium => 48.0,
        AppButtonSize.large => 56.0,
      };

  Widget _content(Widget? spinner) {
    if (loading) {
      spinner ??= const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      return spinner;
    }
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 6),
        ],
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PlatformAdapter.isIOS) {
      return _buildIOS(context);
    }
    return _buildMaterial(context);
  }

  Widget _buildIOS(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (variant) {
      AppButtonVariant.destructive => CupertinoColors.destructiveRed,
      _ => scheme.primary,
    };
    final filled = variant == AppButtonVariant.primary ||
        variant == AppButtonVariant.destructive;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _minHeight),
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: size == AppButtonSize.small ? 6 : 12,
        ),
        color: filled ? color : null,
        onPressed: loading ? null : onPressed,
        child: _content(const CupertinoActivityIndicator(radius: 8)),
      ),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final radius = switch (size) {
      AppButtonSize.small => 8.0,
      AppButtonSize.medium => 12.0,
      AppButtonSize.large => 16.0,
    };
    final padding = switch (size) {
      AppButtonSize.small =>
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      AppButtonSize.medium =>
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      AppButtonSize.large =>
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    };
    final baseStyle = ButtonStyle(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      padding: WidgetStateProperty.all(padding),
    );

    final destructiveStyle = baseStyle.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.error.withValues(alpha: 0.4);
        }
        return scheme.error;
      }),
      foregroundColor: WidgetStateProperty.all(scheme.onError),
    );

    final Widget btn = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          style: baseStyle,
          onPressed: loading ? null : onPressed,
          child: _content(null),
        ),
      AppButtonVariant.secondary => OutlinedButton(
          style: baseStyle,
          onPressed: loading ? null : onPressed,
          child: _content(null),
        ),
      AppButtonVariant.text => TextButton(
          style: baseStyle,
          onPressed: loading ? null : onPressed,
          child: _content(null),
        ),
      AppButtonVariant.destructive => FilledButton(
          style: destructiveStyle,
          onPressed: loading ? null : onPressed,
          child: _content(null),
        ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _minHeight),
      child: btn,
    );
  }
}
