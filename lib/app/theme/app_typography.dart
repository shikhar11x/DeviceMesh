import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Text styles. Monospace is used for IDs, codes and metrics, so digits
/// line up (tabular by nature).
class AppText {
  const AppText._();

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.text,
    letterSpacing: 0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.35,
    color: AppColors.text,
  );

  static const TextStyle muted = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: AppColors.textMuted,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1,
    color: AppColors.textMuted,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12.5,
    color: AppColors.text,
  );

  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 6,
    color: AppColors.cyan,
  );
}