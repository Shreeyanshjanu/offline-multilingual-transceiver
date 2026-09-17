import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class BackgroundConnectionCard extends StatelessWidget {
  const BackgroundConnectionCard({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.backgroundConnection;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('BACKGROUND CONNECTION', style: AppTypography.headlineSm),
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep Connection Active in Background'),
            subtitle: const Text(
                'Keep iTantra connected when the app is minimized or removed from Recents.'),
            value: status.enabled,
            onChanged: status.supported && !controller.connectionBusy
                ? controller.setBackgroundConnectionEnabled
                : null,
          ),
        ),
        Text('Connection: ${controller.connectionStateLabel}',
            style: AppTypography.bodyMd),
        Text(
            'Background service: ${status.serviceRunning ? 'BACKGROUND ACTIVE' : 'Inactive'}',
            style: AppTypography.bodySm.copyWith(
                color: status.serviceRunning
                    ? AppColors.tertiary
                    : AppColors.onSurfaceVariant)),
        if (status.unreadCount > 0)
          Text('${status.unreadCount} unread background messages',
              style: AppTypography.bodySm),
        const SizedBox(height: 8),
        Text(
            status.enabled
                ? 'Turning this off stops the persistent connection. You can reconnect from Talk for foreground use.'
                : 'Enable this, then tap Connect in Talk. An ongoing notification provides a Disconnect action.',
            style: AppTypography.bodySm),
        if (status.enabled && !status.notificationsAllowed) ...[
          const SizedBox(height: 8),
          Text(
              'Notifications are off. The connection can still run; Android shows it in Active Apps.',
              style: AppTypography.bodySm),
        ],
        const SizedBox(height: 8),
        Text(
            'Battery restrictions can delay local messages while the screen is off. For greater reliability, review the app’s battery settings. Android can still stop the service.',
            style: AppTypography.bodySm),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.battery_saver_outlined),
              label: const Text('App battery settings'),
              onPressed: status.supported
                  ? controller.openConnectionBatterySettings
                  : null,
            )),
      ]),
    );
  }
}
