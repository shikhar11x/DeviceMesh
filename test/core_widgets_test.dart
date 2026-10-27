import 'package:devicemesh/app/theme/app_colors.dart';
import 'package:devicemesh/app/theme/app_theme.dart';
import 'package:devicemesh/core/widgets/glass_card.dart';
import 'package:devicemesh/core/widgets/section_header.dart';
import 'package:devicemesh/core/widgets/status_chip.dart';
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
      home: Scaffold(body: child),
    );
  }

  testWidgets('core widgets render their content', (tester) async {
    await tester.pumpWidget(host(const Column(
      children: [
        GlassCard(child: Text('Card body')),
        StatusChip(label: 'Online', color: AppColors.mint),
        SectionHeader('Mesh'),
      ],
    )));

    expect(find.text('Card body'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('MESH'), findsOneWidget);
  });

  testWidgets('live chip pulses normally', (tester) async {
    await tester.pumpWidget(host(const StatusChip(
      label: 'Live',
      color: AppColors.cyan,
      pulse: true,
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('live chip stays still when reduce motion is on', (tester) async {
    await tester.pumpWidget(host(
      const StatusChip(label: 'Live', color: AppColors.cyan, pulse: true),
      reduceMotion: true,
    ));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}