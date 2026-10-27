import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';

/// Perspective tilt that follows the finger, with a moving glare.
/// Uses a Listener, so it never competes with scrolling or taps.
/// Springs back on release. Disabled when "reduce motion" is on.
class Tilt3D extends StatefulWidget {
  const Tilt3D({
    super.key,
    required this.child,
    this.maxTilt = 0.14,
    this.radius = AppSpacing.radius,
  });

  final Widget child;

  /// Maximum rotation in radians.
  final double maxTilt;
  final double radius;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> {
  Offset _tilt = Offset.zero;
  Alignment _glare = Alignment.center;
  bool _active = false;

  void _onPointer(PointerEvent event) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final dx = (event.localPosition.dx / size.width * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();
    final dy = (event.localPosition.dy / size.height * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();
    setState(() {
      _active = true;
      _tilt = Offset(dx * widget.maxTilt, -dy * widget.maxTilt);
      _glare = Alignment(dx, dy);
    });
  }

  void _onRelease(PointerEvent event) {
    if (!_active) return;
    setState(() {
      _active = false;
      _tilt = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;

    return Listener(
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onRelease,
      onPointerCancel: _onRelease,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(end: _tilt),
        duration: Duration(milliseconds: _active ? 90 : 420),
        curve: _active ? Curves.easeOut : Curves.elasticOut,
        builder: (context, tilt, child) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(tilt.dy)
              ..rotateY(tilt.dx),
            child: child,
          );
        },
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _active ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      gradient: RadialGradient(
                        center: _glare,
                        radius: 0.9,
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}