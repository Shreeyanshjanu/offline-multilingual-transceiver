import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class TalkPttStation extends StatelessWidget {
  const TalkPttStation(
      {super.key, required this.controller, required this.isHandsFree});

  final AppController controller;
  final bool isHandsFree;

  @override
  Widget build(BuildContext context) {
    final bool active = controller.isListening;
    final bool isLoading = controller.isModelLoading;

    final Color circleColor = active
        ? AppColors.primary
        : (isLoading
            ? AppColors.surfaceContainerHigh
            : AppColors.tertiaryFixed);

    final Color textColor = active
        ? AppColors.onPrimary
        : (isLoading ? AppColors.primary : AppColors.onTertiaryFixed);

    void showLoadingWarning() {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Speech model is in midst of loading. Please wait 1 to 2 seconds.'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }

    return Center(
      child: Column(
        children: <Widget>[
          Semantics(
            button: true,
            label: isLoading
                ? 'Speech model loading, please wait 1 to 2 seconds'
                : 'Push to talk button',
            hint: isLoading
                ? 'Wait for model to finish loading'
                : (isHandsFree
                    ? 'Tap once to begin speech broadcast'
                    : 'Press and hold to broadcast voice, release when finished'),
            value: active
                ? 'Transmitting audio live'
                : (isLoading ? 'Loading' : 'Ready'),
            child: GestureDetector(
              onTap: isHandsFree
                  ? () {
                      if (isLoading) {
                        showLoadingWarning();
                        return;
                      }
                      if (active) {
                        controller.stopPushToTalk();
                      } else {
                        controller.startPushToTalk();
                      }
                    }
                  : null,
              onTapDown: isHandsFree
                  ? null
                  : (_) {
                      if (isLoading) {
                        showLoadingWarning();
                        return;
                      }
                      controller.startPushToTalk();
                    },
              onTapUp: isHandsFree ? null : (_) => controller.stopPushToTalk(),
              onTapCancel:
                  isHandsFree ? null : () => controller.stopPushToTalk(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: circleColor,
                  border: isLoading
                      ? Border.all(
                          color: AppColors.primary.withValues(alpha: 0.8),
                          width: 2)
                      : null,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: (active
                              ? AppColors.primary
                              : (isLoading
                                  ? AppColors.primary
                                  : AppColors.tertiary))
                          .withValues(
                              alpha: active ? 0.65 : (isLoading ? 0.35 : 0.28)),
                      blurRadius: active ? 36 : (isLoading ? 24 : 18),
                      spreadRadius: active ? 6 : (isLoading ? 2 : 0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        active
                            ? Icons.radio_button_checked
                            : (isLoading ? Icons.hourglass_top : Icons.mic),
                        size: 40,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? 'TRANSMITTING'
                          : (isLoading
                              ? 'LOADING MODEL'
                              : (isHandsFree
                                  ? 'TAP TO SPEAK'
                                  : 'HOLD TO TALK')),
                      style: AppTypography.headlineLg.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      active
                          ? (isHandsFree ? 'Tap to stop' : 'Release when done')
                          : (isLoading
                              ? 'Wait 1-2 seconds'
                              : (isHandsFree
                                  ? 'Tap once to begin'
                                  : 'Release to send')),
                      style: AppTypography.labelCaps.copyWith(
                        color: textColor.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isLoading
                ? 'Speech model loading in background • Please wait 1-2 seconds'
                : (isHandsFree
                    ? 'Hands-Free: Tap once to start, tap again to finalize'
                    : 'Hold anywhere on circle to speak • Release to send'),
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
