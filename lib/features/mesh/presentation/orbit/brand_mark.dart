import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import 'orbit_math.dart';
import 'orbit_node_art.dart';

/// DeviceMesh logo: four interconnected nodes (a tetrahedron) turning slowly
/// in 3D. Static when "reduce motion" is on.
class BrandMark extends StatefulWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(_turn),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.turn) : super(repaint: turn);

  final Animation<double> turn;

  static const List<Vec3> _vertices = [
    Vec3(0.9, 0.9, 0.9),
    Vec3(0.9, -0.9, -0.9),
    Vec3(-0.9, 0.9, -0.9),
    Vec3(-0.9, -0.9, 0.9),
  ];
  static const List<Color> _colors = [
    AppColors.cyan,
    AppColors.violet,
    AppColors.mint,
    AppColors.cyan,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final unit = size.width * 0.24;
    final yaw = turn.value * 2 * math.pi + 0.6;
    final points = [
      for (final v in _vertices)
        OrbitMath.project(OrbitMath.rotateX(OrbitMath.rotateY(v, yaw), 0.35)),
    ];
    Offset at(Projected p) => center + Offset(p.x * unit, p.y * unit);

    final edge = Paint()
      ..strokeWidth = 1.3
      ..color = AppColors.cyan.withValues(alpha: 0.5);
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        canvas.drawLine(at(points[i]), at(points[j]), edge);
      }
    }

    final order = List<int>.generate(points.length, (i) => i)
      ..sort((a, b) => points[b].depth.compareTo(points[a].depth));
    for (final i in order) {
      OrbitNodeArt.sphere(canvas, at(points[i]), 3.6 * points[i].scale, _colors[i]);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}