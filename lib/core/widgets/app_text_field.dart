import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// Themed text field. Built explicitly (not via the global theme) so it
/// does not depend on Material theme API changes.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.keyboardType,
    this.maxLength,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputType? keyboardType;
  final int? maxLength;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      cursorColor: AppColors.cyan,
      style: AppText.mono.copyWith(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        counterText: '',
        filled: true,
        fillColor: AppColors.background.withValues(alpha: 0.6),
        labelStyle: AppText.muted,
        border: _outline(AppColors.border),
        enabledBorder: _outline(AppColors.border),
        focusedBorder: _outline(AppColors.cyan),
        disabledBorder: _outline(AppColors.border.withValues(alpha: 0.08)),
      ),
    );
  }

  static OutlineInputBorder _outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );
}