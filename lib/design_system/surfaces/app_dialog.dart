import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../platform/platform_adapter.dart';

/// AppDialog — Design System 对话框
///
/// 业务代码：
/// ```
/// final ok = await AppDialog.confirm(
///   context,
///   title: '删除照片',
///   message: '确定删除？',
/// );
/// ```
///
/// 平台：
/// - iOS → CupertinoAlertDialog
/// - Android → Material AlertDialog
///
/// 业务层不得直接调用平台 Dialog API。
class AppDialog {
  /// 显示确认对话框
  /// 返回 true 表示用户点击"确定"，false 表示"取消"或关闭
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '确定',
    String cancelLabel = '取消',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        if (PlatformAdapter.isIOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cancelLabel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: destructive,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          );
        }
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructive
                  ? TextButton.styleFrom(
                      foregroundColor: Theme.of(ctx).colorScheme.error,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// 显示信息对话框（仅关闭按钮）
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String okLabel = '确定',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        if (PlatformAdapter.isIOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: Text(okLabel),
              ),
            ],
          );
        }
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(okLabel),
            ),
          ],
        );
      },
    );
  }
}
