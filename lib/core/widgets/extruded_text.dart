import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Text with a stacked-layer 3D extrusion and a soft glow.
/// Cheap: a few Text widgets, no shaders.
class ExtrudedText extends StatelessWidget {
  const ExtrudedText(
    this.text, {
    super.key,
    required this.style,
    this.color = AppColors.cyan,
    this.layers = 6,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final int layers;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = layers; i >= 1; i--)
          Transform.translate(
            offset: Offset(i * 0.7, i * 0.9),
            child: Text(text, style: style.copyWith(color: _shade(i))),
          ),
        Text(
          text,
          style: style.copyWith(
            color: color,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.55), blurRadius: 18),
            ],
          ),
        ),
      ],
    );
  }

  /// Deeper layers fade toward the background color.
  Color _shade(int depth) {
    final mix = (0.45 + depth * 0.08).clamp(0.0, 0.95).toDouble();
    return Color.lerp(color, AppColors.background, mix)!;
  }
}