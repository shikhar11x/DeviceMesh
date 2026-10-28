import 'dart:math' as math;

/// A point in 3D space. The camera looks along +z, so larger z is farther.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

/// A point after perspective projection.
class Projected {
  const Projected({
    required this.x,
    required this.y,
    required this.scale,
    required this.depth,
  });

  final double x;
  final double y;

  /// 1.0 at z = 0, smaller when farther, larger when nearer.
  final double scale;

  /// Rotated z value. Larger means farther from the camera.
  final double depth;
}

/// Pure 3D math for the mesh view. No Flutter imports, so it is testable.
class OrbitMath {
  const OrbitMath._();

  static const double ringRadius = 1.4;
  static const double cameraDistance = 5;

  static Vec3 rotateY(Vec3 p, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
  }

  static Vec3 rotateX(Vec3 p, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
  }

  static Projected project(Vec3 p, {double distance = cameraDistance}) {
    final scale = distance / (distance + p.z);
    return Projected(x: p.x * scale, y: p.y * scale, scale: scale, depth: p.z);
  }

  /// Evenly spaced slots on a ring in the XZ plane. A small, deterministic
  /// height offset gives the ring some depth.
  static List<Vec3> ring(int count, {double radius = ringRadius}) {
    return [
      for (var i = 0; i < count; i++)
        Vec3(
          radius * math.cos(2 * math.pi * i / count),
          0.2 * math.sin(i * 2.1),
          radius * math.sin(2 * math.pi * i / count),
        ),
    ];
  }
}