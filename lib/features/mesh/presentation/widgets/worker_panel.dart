import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../application/worker_controller.dart';
import 'worker_actions.dart';
import 'worker_status.dart';

class WorkerPanel extends ConsumerStatefulWidget {
  const WorkerPanel({super.key});

  @override
  ConsumerState<WorkerPanel> createState() => _WorkerPanelState();
}

class _WorkerPanelState extends ConsumerState<WorkerPanel> {
  final _host = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (connected, paired) =
        ref.watch(workerProvider.select((s) => (s.connected, s.paired)));
    final ctrl = ref.read(workerProvider.notifier);

    return GlassCard(
      accent: AppColors.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Worker', trailing: WorkerStatusChip()),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _host,
            label: 'Coordinator IP (e.g. 192.168.1.5)',
            enabled: !connected,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _code,
            label: '6-digit pairing code',
            enabled: connected && !paired,
            keyboardType: TextInputType.number,
            maxLength: 6,
            helper: connected ? null : 'Connect to the coordinator first',
          ),
          const SizedBox(height: AppSpacing.md),
          WorkerActions(
            onConnect: () => ctrl.connect(_host.text),
            onPair: () => ctrl.pair(_code.text.trim()),
          ),
          if (paired) ...[
            const SizedBox(height: AppSpacing.md),
            const LatencyReadout(),
          ],
        ],
      ),
    );
  }
}