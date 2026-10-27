import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../application/log_provider.dart';

class LogView extends ConsumerWidget {
  const LogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logProvider);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Log',
            trailing: TextButton(
              onPressed: ref.read(logProvider.notifier).clear,
              child: const Text('Clear'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (logs.isEmpty) const Text('Nothing yet', style: AppText.muted),
          for (final line in logs.take(40))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: AppText.mono
                    .copyWith(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}