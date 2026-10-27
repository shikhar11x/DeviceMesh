import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tilt_card.dart';
import '../../mesh/application/coordinator_controller.dart';
import '../domain/mesh_device.dart';

/// Registry view: every device that joined, with advertised capabilities.
class DevicesSection extends ConsumerWidget {
  const DevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(coordinatorProvider.select((s) => s.devices));
    final ctrl = ref.read(coordinatorProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Devices (${devices.length})'),
        const SizedBox(height: AppSpacing.sm),
        if (devices.isEmpty)
          const Text('No devices have joined yet', style: AppText.muted),
        for (final d in devices)
          _DeviceTile(
            key: ValueKey(d.id),
            device: d,
            onRevoke: () => ctrl.revoke(d.id),
          ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    super.key,
    required this.device,
    required this.onRevoke,
  });

  final MeshDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final online = device.isOnline;
    final color = online ? AppColors.cyan : AppColors.red;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Tilt3D(
        maxTilt: 0.05,
        radius: 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.name,
                        style:
                            AppText.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusChip(
                      label: online ? 'Online' : 'Offline',
                      color: color,
                      pulse: online,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  shortId(device.id),
                  style: AppText.mono.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Text(_capabilitySummary(device), style: AppText.muted),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: onRevoke,
                    child: const Text('Revoke'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _capabilitySummary(MeshDevice d) {
  final c = d.capabilities;
  if (c == null) return 'Capabilities: not advertised yet';
  final tasks = c.supportedTasks.map((t) => t.wire).join(', ');
  return 'Tasks: ${tasks.isEmpty ? 'none' : tasks}'
      '  |  ${c.processorCount} cores'
      '  |  max ${c.maxConcurrentTasks} concurrent';
}