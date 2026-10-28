import 'dart:math' as math;

import 'package:devicemesh/features/mesh/presentation/orbit/orbit_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rotateY by a quarter turn maps +x to -z', () {
    final p = OrbitMath.rotateY(const Vec3(1, 0, 0), math.pi / 2);
    expect(p.x, closeTo(0, 1e-9));
    expect(p.y, 0);
    expect(p.z, closeTo(-1, 1e-9));
  });

  test('rotateX by a quarter turn maps +y to +z', () {
    final p = OrbitMath.rotateX(const Vec3(0, 1, 0), math.pi / 2);
    expect(p.x, 0);
    expect(p.y, closeTo(0, 1e-9));
    expect(p.z, closeTo(1, 1e-9));
  });

  test('a full turn returns the same point', () {
    final p = OrbitMath.rotateY(const Vec3(0.3, 0.2, -0.7), 2 * math.pi);
    expect(p.x, closeTo(0.3, 1e-9));
    expect(p.y, closeTo(0.2, 1e-9));
    expect(p.z, closeTo(-0.7, 1e-9));
  });

  test('perspective: far points shrink, near points grow', () {
    expect(OrbitMath.project(const Vec3(0, 0, 0)).scale, 1);
    final far = OrbitMath.project(const Vec3(1, 1, 2));
    final near = OrbitMath.project(const Vec3(1, 1, -2));
    expect(far.scale, lessThan(1));
    expect(near.scale, greaterThan(1));
    expect(far.x, lessThan(near.x));
  });

  group('ring', () {
    test('has one slot per device and none when empty', () {
      expect(OrbitMath.ring(0), isEmpty);
      expect(OrbitMath.ring(1), hasLength(1));
      expect(OrbitMath.ring(5), hasLength(5));
    });

    test('slots lie on the ring radius in the XZ plane', () {
      for (final p in OrbitMath.ring(6)) {
        final r = math.sqrt(p.x * p.x + p.z * p.z);
        expect(r, closeTo(OrbitMath.ringRadius, 1e-9));
      }
    });

    test('positions are deterministic', () {
      final a = OrbitMath.ring(4);
      final b = OrbitMath.ring(4);
      for (var i = 0; i < 4; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
        expect(a[i].z, b[i].z);
      }
    });
  });
}