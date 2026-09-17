import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class SpeechModelsCard extends StatelessWidget {
  const SpeechModelsCard({super.key, required this.controller});

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
            children: <Widget>[
              const Icon(Icons.psychology,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'SPEECH PIPELINE MODELS',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.headlineSm.copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Active offline AI speech recognition and synthesis engines.',
            style: AppTypography.bodySm.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 10),

          // STT Model Details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.mic, size: 16, color: AppColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'OFFLINE STT (SPEECH-TO-TEXT)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.secondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        controller.sttModelName,
                        style: AppTypography.telemetrySm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: controller.isModelLoading
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.tertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    controller.isModelLoading
                        ? 'LOADING...'
                        : (controller.isSttReady ? 'ACTIVE' : 'UNAVAILABLE'),
                    style: AppTypography.labelCaps.copyWith(
                      color: controller.isModelLoading
                          ? AppColors.primary
                          : AppColors.tertiary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // TTS Engine Details
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.volume_up,
                    size: 16, color: AppColors.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'NATIVE TTS (TEXT-TO-SPEECH)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.tertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        controller.ttsModelName,
                        style: AppTypography.telemetrySm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.tertiary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (controller.isModelLoading) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.modelLoadingMessage ??
                          'In midst of loading. Please wait 1 to 2 seconds...',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
