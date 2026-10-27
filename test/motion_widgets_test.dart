import 'package:devicemesh/app/theme/app_theme.dart';
import 'package:devicemesh/core/widgets/staggered_entrance.dart';
import 'package:devicemesh/core/widgets/tilt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) {
    return MaterialApp(
      theme: AppTheme.dark,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Finder inside(Type parent, Type child) =>
      find.descendant(of: find.byType(parent), matching: find.byType(child));

  testWidgets('entrance starts hidden and finishes fully visible',
      (tester) async {
    await tester.pumpWidget(host(
      const StaggeredEntrance(index: 2, child: Text('Hello')),
    ));
    Opacity opacity() =>
        tester.widget<Opacity>(inside(StaggeredEntrance, Opacity));

    expect(opacity().opacity, 0);
    await tester.pumpAndSettle();
    expect(opacity().opacity, 1);
  });

  testWidgets('entrance is instant when reduce motion is on', (tester) async {
    await tester.pumpWidget(host(
      const StaggeredEntrance(index: 3, child: Text('Hello')),
      reduceMotion: true,
    ));
    final opacity =
        tester.widget<Opacity>(inside(StaggeredEntrance, Opacity));
    expect(opacity.opacity, 1);
  });

  testWidgets('tilt rotates while touched and springs back', (tester) async {
    await tester.pumpWidget(host(
      const Tilt3D(child: SizedBox(width: 200, height: 100)),
    ));
    Transform transform() =>
        tester.widget<Transform>(inside(Tilt3D, Transform).first);

    expect(transform().transform.entry(0, 2).abs(), lessThan(1e-9));

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(Tilt3D)) + const Offset(5, 5),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(transform().transform.entry(0, 2).abs(), greaterThan(0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(transform().transform.entry(0, 2).abs(), lessThan(1e-6));
  });

  testWidgets('tilt is disabled when reduce motion is on', (tester) async {
    await tester.pumpWidget(host(
      const Tilt3D(child: SizedBox(width: 200, height: 100)),
      reduceMotion: true,
    ));
    expect(inside(Tilt3D, Transform), findsNothing);
  });
}