import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Drawing helpers for glowing 3D-looking spheres and labels.
class OrbitNodeArt {
  const OrbitNodeArt._();

  /// Soft glow plus a shaded sphere with an off-center highlight.
  static void sphere(Canvas canvas, Offset center, double radius, Color color) {
    final glowRect = Rect.fromCircle(center: center, radius: radius * 2.6);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
      ).createShader(glowRect);
    canvas.drawCircle(center, radius * 2.6, glow);

    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 0.95,
        colors: [
          Color.lerp(color, Colors.white, 0.65)!,
          color,
          Color.lerp(color, Colors.black, 0.55)!,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(bodyRect);
    canvas.drawCircle(center, radius, body);
  }

  /// Small monospace label centered under a node.
  static void label(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    double alpha,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          color: AppColors.text.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy + radius + 6),
    );
    painter.dispose();
  }
}