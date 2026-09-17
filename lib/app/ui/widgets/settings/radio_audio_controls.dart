import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class RadioAudioControls extends StatefulWidget {
  const RadioAudioControls({super.key, required this.controller});

  final AppController controller;

  @override
  State<RadioAudioControls> createState() => _RadioAudioControlsState();
}

class _RadioAudioControlsState extends State<RadioAudioControls> {
  double? _volume;

  @override
  void initState() {
    super.initState();
    _loadVolume();
  }

  @override
  void didUpdateWidget(RadioAudioControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _loadVolume();
  }

  Future<void> _loadVolume() async {
    final double? volume = await widget.controller.getPlaybackVolume();
    if (mounted) setState(() => _volume = volume);
  }

  Future<void> _setVolume(double volume) async {
    final double? actual = await widget.controller.setPlaybackVolume(volume);
    if (mounted) setState(() => _volume = actual);
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
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
              const Icon(Icons.volume_up, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'SPEAKER & ALERTS',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.headlineSm.copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'Incoming Voice Volume',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.bodyMd,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _volume == null ? 'Unavailable' : '${_volume!.round()}%',
                style: AppTypography.telemetrySm
                    .copyWith(color: AppColors.secondary),
              ),
            ],
          ),
          Slider(
            value: _volume ?? 0,
            min: 0,
            max: 100,
            activeColor: AppColors.primary,
            onChanged: _volume == null
                ? null
                : (double v) => setState(() => _volume = v),
            onChangeEnd: _volume == null ? null : _setVolume,
          ),
          const Divider(color: AppColors.outline, height: 16),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('Emergency Voice Volume Boost',
                  style: AppTypography.bodyMd),
              subtitle: Text(
                'Play incoming SOS speech at maximum volume, then restore the previous volume.',
                style: AppTypography.bodySm.copyWith(fontSize: 11),
              ),
              value: controller.emergencyVolumeBoostEnabled,
              onChanged: controller.setEmergencyVolumeBoost,
            ),
          ),
        ],
      ),
    );
  }
}
