import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Restrained glass-style surface: gradient, hairline border, soft glow.
/// No BackdropFilter, so it stays cheap to paint.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.accent = AppColors.cyan,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.elevated, AppColors.surface],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}