import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../models/speech_message.dart';

class TransmissionMonitor extends StatelessWidget {
  const TransmissionMonitor({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final bool isListening = controller.isListening;
    final String transcript = controller.partialTranscript.trim();
    final SpeechMessage? lastMsg =
        controller.history.isNotEmpty ? controller.history.first : null;

    final String titleText = isListening
        ? 'LIVE TRANSMISSION • ${controller.userProfile.callsign.toUpperCase()}'
        : (lastMsg != null
            ? 'FROM: ${lastMsg.senderCallsign?.toUpperCase() ?? "REMOTE UNIT"} [${lastMsg.senderRole?.toUpperCase() ?? "RADIO"}]'
            : 'WHAT WAS HEARD');

    final String displayText = transcript.isNotEmpty
        ? '“$transcript”'
        : (lastMsg != null
            ? '“${lastMsg.message}”'
            : '“Team standby. Ready for voice mesh transmission.”');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
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
                    Icon(
                      isListening ? Icons.graphic_eq : Icons.record_voice_over,
                      color:
                          isListening ? AppColors.primary : AppColors.secondary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        titleText,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelCaps.copyWith(
                          color: isListening
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Live waveform equalizer bars
              Row(
                children: List<Widget>.generate(6, (int i) {
                  final double height =
                      isListening ? (6.0 + ((i % 3 + 1) * 4.5)) : 5.0;

                  return Container(
                    width: 3.5,
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isListening
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isListening
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  displayText,
                  style: AppTypography.headlineSm.copyWith(
                    color: AppColors.onSurface,
                    height: 1.35,
                    fontSize: 15,
                    fontWeight: transcript.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                if (!isListening && lastMsg?.location != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.location_on,
                          size: 13, color: AppColors.tertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'GPS: ${lastMsg!.location!.formattedCoordinates}${lastMsg.location!.accuracyLabel.isNotEmpty ? " • ${lastMsg.location!.accuracyLabel}" : ""}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.telemetrySm.copyWith(
                            color: AppColors.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isListening &&
                    controller.currentLocation != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.location_on,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'ATTACHED GPS: ${controller.currentLocation!.compactCoordinates}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.telemetrySm.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
