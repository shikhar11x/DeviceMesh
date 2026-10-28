import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../devices/domain/mesh_device.dart';
import 'orbit_math.dart';
import 'orbit_node_art.dart';

/// Camera: spin + fixed pitch, then perspective projection to the canvas.
class _Camera {
  const _Camera({
    required this.center,
    required this.unit,
    required this.yaw,
    required this.pitch,
  });

  final Offset center;
  final double unit;
  final double yaw;
  final double pitch;

  Projected project(Vec3 p) => OrbitMath.project(
        OrbitMath.rotateX(OrbitMath.rotateY(p, yaw), pitch),
      );

  Offset screen(Projected p) => center + Offset(p.x * unit, p.y * unit);
}

class _Node {
  const _Node(this.point, this.device);

  final Projected point;
  final MeshDevice device;
}

/// Draws the 3D mesh: floor grid, orbit ring, links and device spheres.
/// Every node comes from [devices] (the real registry). Nothing is faked.
class MeshOrbitPainter extends CustomPainter {
  MeshOrbitPainter({
    required this.devices,
    required this.running,
    required this.spin,
    required this.yawOffset,
  }) : super(repaint: Listenable.merge([spin, yawOffset]));

  static const double _pitch = 0.55;

  final List<MeshDevice> devices;
  final bool running;
  final Animation<double> spin;
  final ValueNotifier<double> yawOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Camera(
      center: size.center(Offset.zero),
      unit: math.min(size.width, size.height) * 0.27,
      yaw: spin.value * 2 * math.pi + yawOffset.value,
      pitch: _pitch,
    );
    _paintGrid(canvas, cam);
    _paintRing(canvas, cam);
    _paintMesh(canvas, cam);
  }

  void _paintGrid(Canvas canvas, _Camera cam) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = AppColors.cyan.withValues(alpha: 0.07);
    const extent = 1.8;
    const step = 0.6;
    const floor = 0.8;
    for (var v = -extent; v <= extent + 1e-6; v += step) {
      canvas.drawLine(
        cam.screen(cam.project(Vec3(v, floor, -extent))),
        cam.screen(cam.project(Vec3(v, floor, extent))),
        paint,
      );
      canvas.drawLine(
        cam.screen(cam.project(Vec3(-extent, floor, v))),
        cam.screen(cam.project(Vec3(extent, floor, v))),
        paint,
      );
    }
  }

  void _paintRing(Canvas canvas, _Camera cam) {
    const segments = 72;
    const r = OrbitMath.ringRadius;
    final paint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    Projected? previous;
    for (var i = 0; i <= segments; i++) {
      final a = 2 * math.pi * i / segments;
      final current = cam.project(Vec3(r * math.cos(a), 0, r * math.sin(a)));
      final before = previous;
      if (before != null) {
        paint.color = AppColors.violet.withValues(
          alpha: 0.10 + 0.30 * _nearness(current.depth),
        );
        canvas.drawLine(cam.screen(before), cam.screen(current), paint);
      }
      previous = current;
    }
  }

  void _paintMesh(Canvas canvas, _Camera cam) {
    final slots = OrbitMath.ring(devices.length);
    final nodes = <_Node>[
      for (var i = 0; i < devices.length; i++)
        _Node(cam.project(slots[i]), devices[i]),
    ];

    // Links first, so spheres sit on top of them.
    for (final n in nodes) {
      final online = n.device.isOnline;
      final paint = Paint()
        ..strokeWidth = online ? 1.6 : 1.1
        ..color = (online ? AppColors.cyan : AppColors.red)
            .withValues(alpha: online ? 0.5 : 0.28);
      final end = cam.screen(n.point);
      if (online) {
        canvas.drawLine(cam.center, end, paint);
      } else {
        _dashedLine(canvas, cam.center, end, paint);
      }
    }

    // Painter's algorithm: far to near. The center node sits at depth 0.
    nodes.sort((a, b) => b.point.depth.compareTo(a.point.depth));
    var centerDrawn = false;
    for (final n in nodes) {
      if (!centerDrawn && n.point.depth <= 0) {
        _paintCenter(canvas, cam.center);
        centerDrawn = true;
      }
      _paintDevice(canvas, cam, n);
    }
    if (!centerDrawn) _paintCenter(canvas, cam.center);
  }

  void _paintDevice(Canvas canvas, _Camera cam, _Node n) {
    final c = cam.screen(n.point);
    final r = 9 * n.point.scale;
    final online = n.device.isOnline;
    OrbitNodeArt.sphere(canvas, c, r, online ? AppColors.cyan : AppColors.red);

    // Violet ring = this device advertised its capabilities.
    if (online && n.device.capabilities != null) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = AppColors.violet.withValues(alpha: 0.85);
      canvas.drawCircle(c, r * 1.6, ring);
    }

    OrbitNodeArt.label(
      canvas,
      c,
      r,
      n.device.name,
      0.4 + 0.6 * _nearness(n.point.depth),
    );
  }

  void _paintCenter(Canvas canvas, Offset c) {
    const r = 15.0;
    if (running) {
      // Expanding ring shows that the coordinator is listening.
      final t = (spin.value * 12) % 1;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.cyan.withValues(alpha: (1 - t) * 0.35);
      canvas.drawCircle(c, r + t * 28, ring);
    }
    OrbitNodeArt.sphere(
      canvas,
      c,
      r,
      running ? AppColors.cyan : AppColors.textMuted,
    );
    OrbitNodeArt.label(canvas, c, r, running ? 'Coordinator' : 'Offline', 0.9);
  }

  /// 1.0 for the nearest point on the ring, 0.0 for the farthest.
  double _nearness(double depth) {
    const r = OrbitMath.ringRadius;
    return (1 - (depth + r) / (2 * r)).clamp(0.0, 1.0).toDouble();
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
    }
  }

  @override
  bool shouldRepaint(MeshOrbitPainter old) =>
      old.devices != devices || old.running != running;
}