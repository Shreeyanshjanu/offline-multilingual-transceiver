import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class ConnectionStatusStrip extends StatelessWidget {
  const ConnectionStatusStrip({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          Text(controller.connectionStateLabel,
              style: AppTypography.labelCaps.copyWith(
                  color: controller.isConnected
                      ? AppColors.tertiary
                      : AppColors.onSurfaceVariant)),
          if (controller.backgroundConnection.serviceRunning)
            Text('BACKGROUND ACTIVE',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.secondary)),
          if (controller.connectionBusy)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      );
}
