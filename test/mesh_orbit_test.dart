import 'dart:ui' as ui;

import 'package:devicemesh/app/theme/app_theme.dart';
import 'package:devicemesh/features/devices/domain/device_capabilities.dart';
import 'package:devicemesh/features/devices/domain/mesh_device.dart';
import 'package:devicemesh/features/mesh/presentation/orbit/mesh_orbit_painter.dart';
import 'package:devicemesh/features/mesh/presentation/orbit/mesh_orbit_view.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const caps = DeviceCapabilities(
    supportedTasks: {TaskType.checksum},
    maxConcurrentTasks: 1,
    imageFormats: [],
    processorCount: 4,
  );

  MeshOrbitPainter painter(List<MeshDevice> devices, {bool running = true}) {
    return MeshOrbitPainter(
      devices: devices,
      running: running,
      spin: const AlwaysStoppedAnimation<double>(0.25),
      yawOffset: ValueNotifier<double>(0),
    );
  }

  Widget host({bool reduceMotion = false}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: (context, app) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: app!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: MeshOrbitView()),
        ),
      ),
    );
  }

  testWidgets('painter draws online, offline and empty meshes',
      (tester) async {
    const size = Size(360, 260);
    final devices = [
      const MeshDevice(id: 'a', name: 'Alpha', capabilities: caps),
      const MeshDevice(
          id: 'b', name: 'Beta', status: ConnectionStatus.offline),
      const MeshDevice(id: 'c', name: 'Gamma'),
    ];
    // Should paint without throwing in every state.
    painter(devices).paint(Canvas(ui.PictureRecorder()), size);
    painter(const []).paint(Canvas(ui.PictureRecorder()), size);
    painter(const [], running: false).paint(Canvas(ui.PictureRecorder()), size);
  });

  testWidgets('painter repaints only when devices or state change',
      (tester) async {
    final devices = [const MeshDevice(id: 'a', name: 'Alpha')];
    final base = painter(devices);
    expect(base.shouldRepaint(painter(devices)), isFalse);
    expect(base.shouldRepaint(painter([...devices])), isTrue);
    expect(base.shouldRepaint(painter(devices, running: false)), isTrue);
  });

  testWidgets('view shows the offline caption and accepts a drag',
      (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Start the coordinator to open the mesh.'),
        findsOneWidget);

    await tester.drag(find.byType(MeshOrbitView), const Offset(80, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('view rotates normally', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('view is static when reduce motion is on', (tester) async {
    await tester.pumpWidget(host(reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}