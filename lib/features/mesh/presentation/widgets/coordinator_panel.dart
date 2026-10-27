import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../devices/presentation/devices_section.dart';
import '../../../pairing/presentation/join_requests_section.dart';
import '../../application/coordinator_controller.dart';
import 'pairing_code_card.dart';
import 'server_address_list.dart';

class CoordinatorPanel extends ConsumerWidget {
  const CoordinatorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(coordinatorProvider.select((s) => s.running));
    final ctrl = ref.read(coordinatorProvider.notifier);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Coordinator',
            trailing: StatusChip(
              label: running ? 'Listening' : 'Stopped',
              color: running ? AppColors.cyan : AppColors.textMuted,
              pulse: running,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: running ? null : ctrl.start,
                  child: const Text('Start server'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: running ? ctrl.stop : null,
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
          if (running) ...const [
            SizedBox(height: AppSpacing.lg),
            ServerAddressList(),
            SizedBox(height: AppSpacing.lg),
            PairingCodeCard(),
            SizedBox(height: AppSpacing.lg),
            JoinRequestsSection(),
            SizedBox(height: AppSpacing.lg),
            DevicesSection(),
          ],
        ],
      ),
    );
  }
}