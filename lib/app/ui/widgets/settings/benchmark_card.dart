import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import 'package:flutter/services.dart';
import '../../../models/benchmark_models.dart';

class BenchmarkCard extends StatelessWidget {
  const BenchmarkCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final BenchmarkSnapshot? snap = controller.latestBenchmark;
    final ResourceBenchmark res = controller.resourceBenchmark;

    String ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds} ms';

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
              const Icon(Icons.speed, color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'TECHNICIAN BENCHMARKS',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.headlineSm.copyWith(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Precision timing for offline STT and mesh voice transmission.',
            style: AppTypography.bodySm.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 12),

          // Metric Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: <Widget>[
              _MetricTile(label: 'STT LATENCY', value: ms(snap?.sttLatency)),
              _MetricTile(label: 'NETWORK', value: ms(snap?.networkLatency)),
              _MetricTile(label: 'TTS LATENCY', value: ms(snap?.ttsLatency)),
              _MetricTile(
                  label: 'END-TO-END', value: ms(snap?.endToEndLatency)),
              _MetricTile(
                label: 'RTF SPEED',
                value: snap?.rtf?.toStringAsFixed(2) ?? '-',
              ),
              _MetricTile(
                label: 'PEAK RAM',
                value: res.peakRamMb == null
                    ? '-'
                    : '${res.peakRamMb!.toStringAsFixed(1)} MB',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Export Actions
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    side: const BorderSide(color: AppColors.outline),
                  ),
                  onPressed: () {
                    final String? json =
                        controller.exportLatestBenchmarkAsJson();
                    if (json != null) {
                      Clipboard.setData(ClipboardData(text: json));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Benchmark JSON copied to clipboard')),
                      );
                    }
                  },
                  icon: const Icon(Icons.data_object, size: 14),
                  label:
                      const Text('Export JSON', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    side: const BorderSide(color: AppColors.outline),
                  ),
                  onPressed: () {
                    final String? csv = controller.exportLatestBenchmarkAsCsv();
                    if (csv != null) {
                      Clipboard.setData(ClipboardData(text: csv));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Benchmark CSV copied to clipboard')),
                      );
                    }
                  },
                  icon: const Icon(Icons.table_chart, size: 14),
                  label:
                      const Text('Export CSV', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(label, style: AppTypography.labelCaps.copyWith(fontSize: 9)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.telemetryMd.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
