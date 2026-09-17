import 'package:flutter/material.dart';

import '../../../models/gps_location.dart';
import '../../../theme/app_theme.dart';
import '../pulsing_dot.dart';

class OperatorGpsCard extends StatelessWidget {
  const OperatorGpsCard(
      {super.key,
      required this.location,
      required this.shareLocation,
      required this.isRefreshing,
      required this.onRefresh,
      required this.onShareLocationChanged});

  final GpsLocation? location;
  final bool shareLocation;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onShareLocationChanged;

  @override
  Widget build(BuildContext context) {
    final GpsLocation? location = this.location;
    return Container(
      padding: const EdgeInsets.all(12),
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
              Row(
                children: <Widget>[
                  Icon(
                    Icons.satellite_alt,
                    color: shareLocation
                        ? AppColors.tertiary
                        : AppColors.outlineVariant,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'OFFLINE GPS TELEMETRY',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Semantics(
                label: 'Attach GPS coordinates to transmissions',
                child: Switch.adaptive(
                  value: shareLocation,
                  onChanged: onShareLocationChanged,
                  activeTrackColor: AppColors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Direct satellite coordinates are attached to your outgoing transmissions for emergency location and team coordination.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                PulsingDot(
                  color:
                      location != null ? AppColors.tertiary : AppColors.primary,
                  size: 7,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location != null
                        ? '📍 ${location.formattedCoordinates} (${location.accuracyLabel})'
                        : '📍 Acquiring satellite coordinates...',
                    style: AppTypography.telemetrySm.copyWith(
                      color: location != null
                          ? AppColors.onSurface
                          : AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: isRefreshing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          size: 18,
                          color: AppColors.primary,
                        ),
                  tooltip: 'Refresh GPS Fix',
                  onPressed: isRefreshing ? null : onRefresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
