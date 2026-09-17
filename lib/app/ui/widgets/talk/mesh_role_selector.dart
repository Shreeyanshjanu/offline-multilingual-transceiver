import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';

class MeshRoleSelector extends StatelessWidget {
  const MeshRoleSelector(
      {super.key, required this.config, required this.onRoleChanged});

  final ConnectionConfig config;
  final ValueChanged<bool> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onRoleChanged(true),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: config.runAsServer
                          ? AppColors.tertiaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.hub,
                          size: 14,
                          color: config.runAsServer
                              ? AppColors.onTertiaryContainer
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'HOST MESH',
                            textAlign: TextAlign.center,
                            style: AppTypography.labelCaps.copyWith(
                              color: config.runAsServer
                                  ? AppColors.onTertiaryContainer
                                  : AppColors.onSurfaceVariant,
                              fontWeight: config.runAsServer
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onRoleChanged(false),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !config.runAsServer
                          ? AppColors.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.link,
                          size: 14,
                          color: !config.runAsServer
                              ? AppColors.onSecondaryContainer
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'JOIN SQUAD',
                            textAlign: TextAlign.center,
                            style: AppTypography.labelCaps.copyWith(
                              color: !config.runAsServer
                                  ? AppColors.onSecondaryContainer
                                  : AppColors.onSurfaceVariant,
                              fontWeight: !config.runAsServer
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
