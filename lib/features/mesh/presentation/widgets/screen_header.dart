import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/extruded_text.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../application/identity_provider.dart';

class ScreenHeader extends ConsumerWidget {
  const ScreenHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(deviceIdProvider).value;
    final name = id == null ? '...' : deviceNameFor(id);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExtrudedText(
                'DeviceMesh',
                style: AppText.title.copyWith(fontSize: 28),
                layers: 4,
              ),
              const SizedBox(height: 6),
              const Text('Many Devices. One Intelligence.',
                  style: AppText.muted),
            ],
          ),
        ),
        StatusChip(label: name, color: AppColors.violet),
      ],
    );
  }
}