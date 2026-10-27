import 'package:flutter/material.dart';

import '../../app/theme/app_typography.dart';
import 'pulse_dot.dart';

/// Pill showing a live status, tinted with [color].
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseDot(color: color, animate: pulse, size: 7),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.label.copyWith(color: color, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}