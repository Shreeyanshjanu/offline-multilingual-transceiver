import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../operator_profile_sheet.dart';
import '../pulsing_dot.dart';

class RadioOperatorCard extends StatelessWidget {
  const RadioOperatorCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.person_pin,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'OPERATOR & TELEMETRY',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: AppTypography.headlineSm.copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  OperatorProfileSheet.show(context, controller);
                },
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.edit, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'EDIT',
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${controller.userProfile.callsign} • ${controller.userProfile.role}',
            style: AppTypography.bodyLg.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            'Unit: ${controller.userProfile.squad}',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                PulsingDot(
                  color: controller.currentLocation != null
                      ? AppColors.tertiary
                      : AppColors.primary,
                  size: 7,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.currentLocation != null
                        ? '📍 ${controller.currentLocation!.formattedCoordinates} (${controller.currentLocation!.accuracyLabel})'
                        : '📍 Offline GPS Fix: Acquiring satellites...',
                    style: AppTypography.telemetrySm.copyWith(
                      color: controller.currentLocation != null
                          ? AppColors.onSurface
                          : AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
