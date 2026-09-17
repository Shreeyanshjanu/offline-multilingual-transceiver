part of 'app_controller.dart';

extension _NativeEventHandling on AppController {
  void _handleNativeEvent(NativeEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case NativeEventType.connectionState:
        _applyBackgroundStatus(event.payload ?? const <dynamic, dynamic>{});
        break;
      case NativeEventType.incomingMessage:
        final record = event.payload?['record'];
        if (record is Map) _ingestNativeMessage(record);
        break;
      case NativeEventType.connectionError:
        _status = event.text ?? 'Background connection error';
        _notifyStateChanged();
        break;
      case NativeEventType.partial:
        _partialTranscript = event.text ?? _partialTranscript;
        _notifyStateChanged();
        break;
      case NativeEventType.finalSentence:
        if (event.payload?['recognitionValid'] != true ||
            event.payload?['fallback'] == true) {
          _status = 'Rejected unverified or fallback speech result';
          _notifyStateChanged();
          break;
        }
        final String transcript = (event.text ?? '').trim();
        if (transcript.isNotEmpty) {
          final String messageId =
              event.messageId ?? _activeMessageId ?? _newMessageId();
          if (_benchmarkTracker.snapshotFor(messageId).marks.t2SttFinal ==
              null) {
            _benchmarkTracker.mark(messageId, BenchmarkEvent.t2SttFinal);
          }
          final SpeechMessage outgoing = SpeechMessage(
            id: messageId,
            type: MessageType.speech,
            languageCode: event.payload?['languageCode']?.toString() ??
                _selectedLanguage.code,
            message: transcript,
            timestamp: DateTime.now(),
            origin: MessageOrigin.local,
            senderCallsign: _userProfile.callsign,
            senderRole: _userProfile.role,
            senderSquad: _userProfile.squad,
            location: _userProfile.shareLocation ? _currentLocation : null,
          );
          unawaited(_sendOutgoingMessage(outgoing));
        }
        break;
      case NativeEventType.ttsStarted:
        if (event.messageId != null) {
          _benchmarkTracker.mark(event.messageId!, BenchmarkEvent.t5TtsStart);
          _status = 'TTS started';
          _notifyStateChanged();
        }
        break;
      case NativeEventType.audioStarted:
        if (event.messageId != null) {
          _benchmarkTracker.mark(
            event.messageId!,
            BenchmarkEvent.t6AudioFirstFrame,
          );
          _recordBenchmark(
            _benchmarkTracker.snapshotFor(
              event.messageId!,
              audioDuration: _estimateAudioDuration(event.text ?? ''),
            ),
          );

          final SpeechMessage? message = _lookupMessage(event.messageId!);
          if (message != null) {
            _status = message.type == MessageType.emergency
                ? 'Emergency alert played'
                : 'Message played';
          }

          _notifyStateChanged();
        }
        break;
      case NativeEventType.resourceMetrics:
        final ResourceBenchmark? resource =
            _parseResourceBenchmark(event.payload);
        if (resource != null) {
          _benchmarkTracker.updateResourceUsage(resource);
          final BenchmarkSnapshot? snapshot = _latestBenchmark;
          if (snapshot != null) {
            _recordBenchmark(
              _benchmarkTracker.snapshotFor(
                snapshot.messageId,
                audioDuration: snapshot.audioDuration,
                processingDuration: snapshot.processingDuration,
              ),
            );
          }
          _notifyStateChanged();
        }
        break;
      case NativeEventType.captureState:
        if (event.payload?['captureId'] != _activeMessageId) break;
        if (event.payload?['state'] == 'recording') {
          _isListening = !_stopRequested;
          if (!_stopRequested) {
            _status = event.text ?? 'Listening';
          }
          if (event.messageId != null) {
            _benchmarkTracker.mark(
                event.messageId!, BenchmarkEvent.t0SpeechStart,
                at: event.timestamp);
          }
        } else if (event.payload?['state'] == 'stopped') {
          _capturePending = false;
          _isListening = false;
          _stopRequested = false;
          _activeMessageId = null;
          if (event.payload?['failed'] == true ||
              _status.startsWith('Finishing') ||
              _status.startsWith('Starting')) {
            _status = event.text ?? 'Recording finished';
          }
        }
        _notifyStateChanged();
        break;
      case NativeEventType.sttReady:
        if (!_isCurrentLanguageEvent(event)) break;
        _sttReady = event.payload?['available'] == true;
        _isModelLoading = false;
        _modelLoadingMessage = null;
        _status = event.text ?? (_sttReady! ? 'STT ready' : 'STT unavailable');
        _notifyStateChanged();
        break;
      case NativeEventType.sttMetrics:
        _latestSttMetrics = Map<String, dynamic>.from(
            event.payload ?? const <String, dynamic>{});
        debugPrint('STT AUDIO: $_latestSttMetrics');
        _recordMeasuredAudio(event);
        _notifyStateChanged();
        break;
      case NativeEventType.captureMetrics:
        _latestCaptureMetrics = Map<String, dynamic>.from(
            event.payload ?? const <String, dynamic>{});
        debugPrint('CAPTURE AUDIO: $_latestCaptureMetrics');
        _notifyStateChanged();
        break;
      case NativeEventType.modelLoading:
        if (!_isCurrentLanguageEvent(event)) break;
        _isModelLoading = true;
        _modelLoadingMessage = event.payload?['message']?.toString() ??
            'Loading speech model... Please wait 1-2s';
        if (event.payload?['sttModel'] != null) {
          _sttModelName = event.payload!['sttModel'].toString();
        }
        if (event.payload?['ttsModel'] != null) {
          _ttsModelName = event.payload!['ttsModel'].toString();
        }
        _status = _modelLoadingMessage!;
        _notifyStateChanged();
        break;
      case NativeEventType.modelReady:
        if (!_isCurrentLanguageEvent(event)) break;
        _isModelLoading = false;
        _modelLoadingMessage = null;
        if (event.payload?['sttModel'] != null) {
          _sttModelName = event.payload!['sttModel'].toString();
        }
        if (event.payload?['ttsModel'] != null) {
          _ttsModelName = event.payload!['ttsModel'].toString();
        }
        if (event.payload?['sttAvailable'] != null) {
          _sttReady = event.payload!['sttAvailable'] == true;
        }
        _status =
            event.payload?['message']?.toString() ?? 'Speech models ready';
        _notifyStateChanged();
        break;
      case NativeEventType.status:
        if ((event.text ?? '').isNotEmpty) {
          _status = event.text!;
          _notifyStateChanged();
        }
        break;
      case NativeEventType.error:
        if (event.payload?['operation'] == 'setLanguage' ||
            event.payload?['operation'] == 'initializePipelines') {
          _isModelLoading = false;
          _modelLoadingMessage = null;
          _sttReady = false;
        }
        if (event.payload?['captureError'] == true &&
            event.payload?['captureId'] == _activeMessageId) {
          _capturePending = false;
          _isListening = false;
          _stopRequested = false;
          _activeMessageId = null;
        }
        _status = 'Native error: ${event.text ?? 'unknown'}';
        _notifyStateChanged();
        break;
    }
  }

  bool _isCurrentLanguageEvent(NativeEvent event) {
    final Object? code = event.payload?['languageCode'];
    return code == null || code == _selectedLanguage.code;
  }
}
