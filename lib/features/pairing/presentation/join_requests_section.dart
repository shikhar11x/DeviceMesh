import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/tilt_card.dart';
import '../../../services/networking/mesh_server.dart';
import '../../mesh/application/coordinator_controller.dart';

/// Devices that presented a valid code and wait for the operator's decision.
class JoinRequestsSection extends ConsumerWidget {
  const JoinRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(coordinatorProvider.select((s) => s.pending));
    final ctrl = ref.read(coordinatorProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Join requests'),
        const SizedBox(height: AppSpacing.sm),
        if (pending.isEmpty)
          const Text('No pending requests', style: AppText.muted),
        for (final r in pending)
          _JoinRequestTile(
            key: ValueKey(r.deviceId),
            request: r,
            onApprove: () => ctrl.approve(r.deviceId),
            onReject: () => ctrl.reject(r.deviceId),
          ),
      ],
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final PeerInfo request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Tilt3D(
        maxTilt: 0.05,
        radius: 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.deviceName,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  shortId(request.deviceId),
                  style: AppText.mono.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onApprove,
                        child: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}