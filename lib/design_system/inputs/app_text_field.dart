import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../platform/platform_adapter.dart';

/// AppTextField — Design System 文本输入框
///
/// 平台：
/// - iOS → CupertinoTextField
/// - Android → Material TextField
///
/// 业务层不得直接调用平台 TextField。
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final bool expands;
  final TextInputType? keyboardType;
  final EdgeInsetsGeometry? contentPadding;

  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.expands = false,
    this.keyboardType,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformAdapter.isIOS) {
      return CupertinoTextField(
        controller: controller,
        placeholder: hintText,
        maxLines: expands ? null : maxLines,
        minLines: expands ? null : minLines,
        onChanged: onChanged,
        keyboardType: keyboardType,
        padding: contentPadding as EdgeInsets? ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.systemGrey4),
        ),
      );
    }
    return TextField(
      controller: controller,
      decoration: InputDecoration(hintText: hintText),
      maxLines: expands ? null : maxLines,
      minLines: expands ? null : minLines,
      onChanged: onChanged,
      keyboardType: keyboardType,
      expands: expands,
    );
  }
}
