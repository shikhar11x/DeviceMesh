import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/section_header.dart';
import '../../application/coordinator_controller.dart';

/// Addresses other phones can type into the Worker panel.
class ServerAddressList extends ConsumerWidget {
  const ServerAddressList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses =
        ref.watch(coordinatorProvider.select((s) => s.addresses));
    final port = ref.watch(coordinatorProvider.select((s) => s.port));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Connect to'),
        const SizedBox(height: AppSpacing.sm),
        if (addresses.isEmpty)
          const Text(
            'No network address found. Join Wi-Fi or enable a hotspot.',
            style: AppText.muted,
          ),
        for (final a in addresses)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText(
              '$a  :$port',
              style: AppText.mono.copyWith(color: AppColors.cyan),
            ),
          ),
      ],
    );
  }
}