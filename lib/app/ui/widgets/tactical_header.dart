import 'dart:ui';
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import 'language_picker_sheet.dart';
import 'operator_profile_sheet.dart';
import 'radio_settings_sheet.dart';

class TacticalHeader extends StatelessWidget {
  const TacticalHeader({
    super.key,
    required this.controller,
    required this.activeTabTitle,
  });

  final AppController controller;
  final String activeTabTitle;

  @override
  Widget build(BuildContext context) {
    final bool connected = controller.isConnected;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 4,
            bottom: 8,
            left: 12,
            right: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.92),
            border: const Border(
              bottom: BorderSide(color: AppColors.outline, width: 1),
            ),
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double availableWidth = constraints.maxWidth;
              final bool isUltraCompact = availableWidth < 340;
              final bool isCompact = availableWidth < 390;

              // Language label: short uppercase code on compact/narrow displays (e.g. 'EN', 'HI')
              final String langText = isCompact
                  ? controller.selectedLanguage.code.toUpperCase()
                  : controller.selectedLanguage.label.split(' ').first;

              final double maxCallsignWidth =
                  isUltraCompact ? 48 : (isCompact ? 60 : 76);
              final double maxLangWidth = isCompact ? 24 : 52;

              return Row(
                children: <Widget>[
                  // Tactical Voice Logo & App Title (wrapped in Flexible so it yields space gracefully)
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.6),
                            ),
                          ),
                          child: const Icon(
                            Icons.sensors,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                isUltraCompact ? 'VOICE' : 'OFFLINE VOICE',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.headlineSm.copyWith(
                                  fontSize: isUltraCompact ? 11.5 : 12.5,
                                  letterSpacing: 0.3,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (!isUltraCompact)
                                Text(
                                  'CH 01 • MESH',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.secondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Right-side Action Controls Group
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Operator Profile Chip
                      Semantics(
                        button: true,
                        label:
                            'Operator: ${controller.userProfile.callsign}. Tap to edit profile.',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () =>
                                OperatorProfileSheet.show(context, controller),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minHeight: 48, minWidth: 48),
                              child: Center(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 5 : 7,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(
                                        Icons.person,
                                        color: AppColors.primary,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 3),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: maxCallsignWidth),
                                        child: Text(
                                          controller.userProfile.callsign,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style:
                                              AppTypography.labelCaps.copyWith(
                                            color: AppColors.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10,
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
                      ),
                      const SizedBox(width: 4),

                      // Global Interactive Language Picker Chip
                      Semantics(
                        button: true,
                        label:
                            'Selected language: ${controller.selectedLanguage.label}. Tap to change.',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () =>
                                LanguagePickerSheet.show(context, controller),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minHeight: 48, minWidth: 48),
                              child: Center(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 5 : 7,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.secondary
                                          .withValues(alpha: 0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(
                                        Icons.translate,
                                        color: AppColors.secondary,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 3),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: maxLangWidth),
                                        child: Text(
                                          langText,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style:
                                              AppTypography.labelCaps.copyWith(
                                            color: AppColors.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ),
                                      if (!isUltraCompact)
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          color: AppColors.onSurfaceVariant,
                                          size: 14,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Diagnostics / Radio Settings Button
                      Semantics(
                        button: true,
                        label: 'Radio diagnostics and settings',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () =>
                                RadioSettingsSheet.show(context, controller),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minHeight: 48, minWidth: 48),
                              child: Center(
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: connected
                                              ? AppColors.tertiary
                                                  .withValues(alpha: 0.6)
                                              : AppColors.outline,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.tune,
                                        size: 16,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                    if (connected)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: AppColors.tertiary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors
                                                  .surfaceContainerLowest,
                                              width: 1.5,
                                            ),
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
