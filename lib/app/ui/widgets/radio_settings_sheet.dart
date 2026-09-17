import 'dart:ui';
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';

import 'settings/radio_operator_card.dart';
import 'settings/radio_audio_controls.dart';
import 'settings/speech_models_card.dart';
import 'settings/benchmark_card.dart';
import 'settings/background_connection_card.dart';

/// Modal bottom sheet for secondary radio controls and technician benchmarks.
class RadioSettingsSheet extends StatefulWidget {
  const RadioSettingsSheet({super.key, required this.controller});

  final AppController controller;

  static Future<void> show(BuildContext context, AppController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => RadioSettingsSheet(controller: controller),
    );
  }

  @override
  State<RadioSettingsSheet> createState() => _RadioSettingsSheetState();
}

class _RadioSettingsSheetState extends State<RadioSettingsSheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(RadioSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.outline),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sheet Header
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.tune,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('RADIO CONFIG & TELEMETRY',
                              style: AppTypography.labelCaps),
                          Text('Speaker & Diagnostics',
                              style: AppTypography.headlineSm),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AppColors.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                BackgroundConnectionCard(controller: controller),
                const SizedBox(height: 14),

                RadioOperatorCard(controller: controller),
                const SizedBox(height: 14),

                RadioAudioControls(controller: controller),
                const SizedBox(height: 14),

                SpeechModelsCard(controller: controller),
                const SizedBox(height: 16),

                BenchmarkCard(controller: controller),
                const SizedBox(height: 16),

                // Version Footer
                Center(
                  child: Text(
                    'iTantra • Offline Voice Radio',
                    style: AppTypography.telemetrySm.copyWith(
                      color: AppColors.outlineVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
