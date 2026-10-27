import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Reminder that the current transport is development-only.
class DevBanner extends StatelessWidget {
  const DevBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.amber, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'DEV MODE: ws:// unencrypted, messages not yet signed',
                style: TextStyle(fontSize: 12.5, color: AppColors.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}