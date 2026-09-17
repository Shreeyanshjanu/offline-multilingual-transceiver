part of 'app_controller.dart';

extension _BenchmarkRecording on AppController {
  void _recordMeasuredAudio(NativeEvent event) {
    final Map<dynamic, dynamic>? metrics = event.payload;
    final String? messageId = event.messageId;
    if (messageId == null ||
        metrics == null ||
        metrics['recognitionValid'] != true) {
      return;
    }
    final double? audioMs = _parseMetric(metrics['audioDurationMs']);
    final double? processingMs = _parseMetric(metrics['processingDurationMs']);
    if (audioMs == null || processingMs == null) return;
    _benchmarkTracker.recordAudioTiming(
      messageId,
      audioDuration: Duration(microseconds: (audioMs * 1000).round()),
      processingDuration: Duration(microseconds: (processingMs * 1000).round()),
    );
    final Map<BenchmarkEvent, String> marks = <BenchmarkEvent, String>{
      BenchmarkEvent.t0SpeechStart: 'audioStartEpochMs',
      BenchmarkEvent.t1SpeechEnd: 'audioEndEpochMs',
      BenchmarkEvent.t2SttFinal: 'recognitionFinishedEpochMs',
    };
    for (final MapEntry<BenchmarkEvent, String> mark in marks.entries) {
      final double? at = _parseMetric(metrics[mark.value]);
      if (at != null) {
        _benchmarkTracker.mark(messageId, mark.key,
            at: DateTime.fromMillisecondsSinceEpoch(at.round()));
      }
    }
    _recordBenchmark(_benchmarkTracker.snapshotFor(messageId));
  }

  Future<void> _persistBenchmarkHistory() async {
    await _benchmarkHistoryStorageService.save(
      snapshots: _benchmarkHistory,
      messageLookup: _lookupMessage,
      appDataPathProvider: _nativeBridgeService.getAppDataDirectoryPath,
    );
  }

  void _restorePersistedBenchmarkHistory(PersistedBenchmarkHistory persisted) {
    _benchmarkHistory.clear();
    _messageById.clear();

    final List<BenchmarkSnapshot> limitedSnapshots = persisted.snapshots
        .take(AppController._maxBenchmarkHistory)
        .toList(growable: false);

    _benchmarkHistory.addAll(limitedSnapshots);
    _latestBenchmark =
        _benchmarkHistory.isEmpty ? null : _benchmarkHistory.first;

    for (final BenchmarkSnapshot snapshot in limitedSnapshots) {
      final SpeechMessage? message = persisted.messagesById[snapshot.messageId];
      if (message != null) {
        _messageById[snapshot.messageId] = message;
      }
    }
  }

  void _recordBenchmark(BenchmarkSnapshot snapshot) {
    _latestBenchmark = snapshot;

    final int existingIndex = _benchmarkHistory.indexWhere(
      (BenchmarkSnapshot item) => item.messageId == snapshot.messageId,
    );
    if (existingIndex >= 0) {
      _benchmarkHistory.removeAt(existingIndex);
    }

    _benchmarkHistory.insert(0, snapshot);
    if (_benchmarkHistory.length > AppController._maxBenchmarkHistory) {
      final List<BenchmarkSnapshot> removed =
          _benchmarkHistory.sublist(AppController._maxBenchmarkHistory);
      for (final BenchmarkSnapshot item in removed) {
        _messageById.remove(item.messageId);
        _benchmarkTracker.clear(item.messageId);
      }
      _benchmarkHistory.removeRange(
        AppController._maxBenchmarkHistory,
        _benchmarkHistory.length,
      );
    }

    unawaited(_persistBenchmarkHistory());
  }

  ResourceBenchmark? _parseResourceBenchmark(Map<dynamic, dynamic>? payload) {
    if (payload == null) {
      return null;
    }

    return ResourceBenchmark(
      sttRamMb: _parseMetric(payload['sttRamMb']),
      ttsRamMb: _parseMetric(payload['ttsRamMb']),
      idleRamMb: _parseMetric(payload['idleRamMb']),
      peakRamMb: _parseMetric(payload['peakRamMb']),
      idleCpuPct: _parseMetric(payload['idleCpuPct']),
      sttCpuPct: _parseMetric(payload['sttCpuPct']),
      ttsCpuPct: _parseMetric(payload['ttsCpuPct']),
      sttModelSizeMb: _parseMetric(payload['sttModelSizeMb']),
      ttsModelSizeMb: _parseMetric(payload['ttsModelSizeMb']),
      apkSizeMb: _parseMetric(payload['apkSizeMb']),
    );
  }

  double? _parseMetric(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
