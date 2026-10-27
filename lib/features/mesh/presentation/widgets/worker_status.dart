import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../application/worker_controller.dart';

class WorkerStatusChip extends ConsumerWidget {
  const WorkerStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (connected, paired) =
        ref.watch(workerProvider.select((s) => (s.connected, s.paired)));

    if (paired) {
      return const StatusChip(
          label: 'Paired', color: AppColors.mint, pulse: true);
    }
    if (connected) {
      return const StatusChip(label: 'Not paired', color: AppColors.amber);
    }
    return const StatusChip(label: 'Offline', color: AppColors.textMuted);
  }
}

/// Round-trip time measured by the worker from HEARTBEAT_ACK.
class LatencyReadout extends ConsumerWidget {
  const LatencyReadout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ms = ref.watch(workerProvider.select((s) => s.latencyMs));

    return Row(
      children: [
        const Text('RTT', style: AppText.label),
        const SizedBox(width: AppSpacing.sm),
        Text(
          ms == null ? '-- ms' : '${ms.toStringAsFixed(1)} ms',
          style: AppText.mono.copyWith(color: AppColors.cyan, fontSize: 15),
        ),
      ],
    );
  }
}