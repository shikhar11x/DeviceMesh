import 'package:flutter/material.dart';

/// DeviceMesh palette. Cyan = active network, violet = computation,
/// mint = completed, amber = warning, red = failure.
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF080B14);
  static const Color surface = Color(0xFF0E1422);
  static const Color elevated = Color(0xFF141C2D);

  static const Color cyan = Color(0xFF45E6FF);
  static const Color violet = Color(0xFF9B7BFF);
  static const Color mint = Color(0xFF54F0B0);
  static const Color amber = Color(0xFFFFBE55);
  static const Color red = Color(0xFFFF5D73);

  static const Color text = Color(0xFFF2F6FF);
  static const Color textMuted = Color(0xFF98A6C3);

  /// Blue-gray at about 16% opacity.
  static const Color border = Color(0x2998A6C3);
}