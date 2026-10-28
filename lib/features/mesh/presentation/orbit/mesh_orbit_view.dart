import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../application/coordinator_controller.dart';
import 'mesh_orbit_painter.dart';

/// Interactive 3D view of the live mesh. Drag sideways to rotate.
class MeshOrbitView extends ConsumerStatefulWidget {
  const MeshOrbitView({super.key});

  @override
  ConsumerState<MeshOrbitView> createState() => _MeshOrbitViewState();
}

class _MeshOrbitViewState extends ConsumerState<MeshOrbitView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );
  final ValueNotifier<double> _yawOffset = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _yawOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(coordinatorProvider.select((s) => s.devices));
    final running = ref.watch(coordinatorProvider.select((s) => s.running));
    final online = devices.where((d) => d.isOnline).length;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Mesh view',
            trailing: StatusChip(
              label: running ? '$online online' : 'Offline',
              color: running ? AppColors.cyan : AppColors.textMuted,
              pulse: running && online > 0,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 240,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) =>
                  _yawOffset.value += d.delta.dx * 0.01,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: MeshOrbitPainter(
                    devices: devices,
                    running: running,
                    spin: _spin,
                    yawOffset: _yawOffset,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_caption(running, devices.length), style: AppText.muted),
        ],
      ),
    );
  }

  String _caption(bool running, int count) {
    if (!running) return 'Start the coordinator to open the mesh.';
    if (count == 0) return 'Waiting for devices to join...';
    return 'Drag sideways to rotate. Violet ring = capabilities advertised.';
  }
}