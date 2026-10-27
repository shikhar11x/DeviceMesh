import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          child: SizedBox(width: 3, height: 14),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(), style: AppText.label)),
        ?trailing,
      ],
    );
  }
}