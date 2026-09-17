import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import '../../../theme/app_theme.dart';

class OperatorIdentityFields extends StatelessWidget {
  const OperatorIdentityFields(
      {super.key,
      required this.callsignController,
      required this.squadController,
      required this.selectedRole,
      required this.onRoleChanged});

  final TextEditingController callsignController;
  final TextEditingController squadController;
  final String selectedRole;
  final ValueChanged<String> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
// Callsign / Name field
        Text(
          'OPERATOR CALLSIGN / NAME',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: callsignController,
          style: AppTypography.bodyLg.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            hintText: 'e.g. Bravo-6, Tanishq, Medic-1',
            hintStyle: AppTypography.bodyLg.copyWith(
              color: AppColors.outlineVariant,
            ),
            prefixIcon: const Icon(
              Icons.badge,
              color: AppColors.primary,
              size: 20,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),

// Tactical Role selection
        Text(
          'TACTICAL ROLE',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: UserProfile.standardRoles.map((String role) {
            final bool isSelected = selectedRole == role;
            return Semantics(
              button: true,
              selected: isSelected,
              label: 'Role $role',
              child: InkWell(
                onTap: () => onRoleChanged(role),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.outline,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        role,
                        style: AppTypography.bodySm.copyWith(
                          color: isSelected
                              ? AppColors.onSurface
                              : AppColors.onSurfaceVariant,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

// Squad Name field
        Text(
          'SQUAD / UNIT NAME',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: squadController,
          style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            hintText: 'Alpha Squad',
            hintStyle: AppTypography.bodyMd.copyWith(
              color: AppColors.outlineVariant,
            ),
            prefixIcon: const Icon(
              Icons.groups,
              color: AppColors.secondary,
              size: 20,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.secondary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
