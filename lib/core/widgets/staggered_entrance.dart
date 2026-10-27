import 'package:flutter/material.dart';

/// 3D reveal: the child rotates up from a tilted plane while fading in.
/// [index] staggers the start. Plays once. Instant when "reduce motion" is on.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  static const int _stepMs = 90;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 520 + widget.index * _stepMs),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = 520 + widget.index * _stepMs;
    final curve = Interval(
      (widget.index * _stepMs) / totalMs,
      1,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = curve.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 28),
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateX((1 - t) * 0.55),
              child: child,
            ),
          ),
        );
      },
    );
  }
}