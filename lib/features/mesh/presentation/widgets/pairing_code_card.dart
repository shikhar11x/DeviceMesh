import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/extruded_text.dart';
import '../../../../core/widgets/tilt_card.dart';
import '../../application/coordinator_controller.dart';

/// Shows the active 6-digit code as 3D extruded text on a tiltable face.
class PairingCodeCard extends ConsumerWidget {
  const PairingCodeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(coordinatorProvider.select((s) => s.code));
    final expires =
        ref.watch(coordinatorProvider.select((s) => s.codeExpiresAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tilt3D(child: _CodeFace(code: code, expires: expires)),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonal(
          onPressed: ref.read(coordinatorProvider.notifier).newCode,
          child: Text(code == null ? 'Generate code' : 'New code'),
        ),
      ],
    );
  }
}

class _CodeFace extends StatelessWidget {
  const _CodeFace({required this.code, required this.expires});

  final String? code;
  final DateTime? expires;

  @override
  Widget build(BuildContext context) {
    final active = code != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: AppColors.cyan.withValues(alpha: active ? 0.4 : 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Text('PAIRING CODE', style: AppText.label),
            const SizedBox(height: AppSpacing.md),
            if (active)
              ExtrudedText(code!, style: AppText.code)
            else
              Text('------',
                  style: AppText.code.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: AppSpacing.sm),
            if (expires != null)
              Text('Expires ${formatHms(expires!)}', style: AppText.muted),
          ],
        ),
      ),
    );
  }
}