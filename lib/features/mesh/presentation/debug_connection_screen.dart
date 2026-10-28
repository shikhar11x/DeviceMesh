import 'package:flutter/material.dart';
import 'orbit/mesh_orbit_view.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/staggered_entrance.dart';
import 'widgets/coordinator_panel.dart';
import 'widgets/dev_banner.dart';
import 'widgets/log_view.dart';
import 'widgets/screen_header.dart';
import 'widgets/worker_panel.dart';

/// Development screen for the pairing milestone. Composition only:
/// all state lives in Riverpod controllers, all UI in small widgets.
class DebugConnectionScreen extends StatelessWidget {
  const DebugConnectionScreen({super.key});

  static const List<Widget> _sections = [
    ScreenHeader(),
    DevBanner(),
    MeshOrbitView(),
    CoordinatorPanel(),
    WorkerPanel(),
    LogView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _sections.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.lg),
                StaggeredEntrance(index: i, child: _sections[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}