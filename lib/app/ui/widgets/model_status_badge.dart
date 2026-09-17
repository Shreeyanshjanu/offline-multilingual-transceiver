import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';

/// Tactical status badge showing active STT and TTS models,
/// with an eye-catching warning notice during model loading.
class ModelStatusBadge extends StatelessWidget {
  const ModelStatusBadge({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool isLoading = controller.isModelLoading;

        if (isLoading) {
          return _buildLoadingBanner(context);
        }

        return _buildReadyBadges(context);
      },
    );
  }

  Widget _buildLoadingBanner(BuildContext context) {
    final String message = controller.modelLoadingMessage ??
        'Midst of loading speech models. Please wait 1 to 2 seconds...';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.8),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(
                      'MODEL LOADING',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      '• WAIT 1-2 SECONDS',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurface,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyBadges(BuildContext context) {
    final String sttName = controller.sttModelName;
    final String ttsName = controller.ttsModelName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          // STT Model Badge
          Expanded(
            child: _ModelChip(
              icon: Icons.mic,
              iconColor: AppColors.secondary,
              prefix: 'STT',
              modelName: sttName,
              tooltip: 'Active Speech-to-Text Model: $sttName',
            ),
          ),
          const SizedBox(width: 8),
          // TTS Model Badge
          Expanded(
            child: _ModelChip(
              icon: Icons.volume_up,
              iconColor: AppColors.tertiary,
              prefix: 'TTS',
              modelName: ttsName,
              tooltip: 'Active Text-to-Speech Engine: $ttsName',
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.icon,
    required this.iconColor,
    required this.prefix,
    required this.modelName,
    required this.tooltip,
  });

  final IconData icon;
  final Color iconColor;
  final String prefix;
  final String modelName;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.outline.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 5),
            Text(
              '$prefix: ',
              style: AppTypography.labelCaps.copyWith(
                color: iconColor,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            Expanded(
              child: Text(
                modelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.telemetrySm.copyWith(
                  color: AppColors.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
