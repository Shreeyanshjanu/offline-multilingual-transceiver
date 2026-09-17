import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../models/operation_mode.dart';

class TalkModeSwitcher extends StatelessWidget {
  const TalkModeSwitcher(
      {super.key, required this.controller, required this.isHandsFree});

  final AppController controller;
  final bool isHandsFree;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ModePill(
              label: 'PTT',
              active: !isHandsFree,
              onTap: () => controller.setOperationMode(
                OperationMode.walkieTalkie,
              ),
            ),
            _ModePill(
              label: 'HANDS-FREE',
              active: isHandsFree,
              onTap: () => controller.setOperationMode(
                OperationMode.continuous,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.surfaceContainerHighest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color:
                    active ? AppColors.onSurface : AppColors.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
