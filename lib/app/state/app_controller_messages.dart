part of 'app_controller.dart';

extension _MessageDispatch on AppController {
  Future<void> _sendOutgoingMessage(SpeechMessage message) async {
    _history.insert(0, message);
    _rememberMessage(message);
    _benchmarkTracker.mark(message.id, BenchmarkEvent.t3MessageSent);

    if (isNetworkActive || _usingNativeConnection) {
      try {
        if (_usingNativeConnection) {
          await _nativeBridgeService
              .sendBackgroundMessage(message.toJsonNetwork());
        } else {
          await _tcpMessageService.send(message);
        }
        _status = 'Message sent';
      } catch (error) {
        _status = 'Send failed: $error';
      }
    } else {
      _status = 'No peer connected. Running one-phone loop.';
      final SpeechMessage loopback = message.copyWith(
        origin: MessageOrigin.remote,
      );
      await _playIncomingMessage(loopback);
    }

    _recordBenchmark(
      _benchmarkTracker.snapshotFor(
        message.id,
        audioDuration: _estimateAudioDuration(message.message),
      ),
    );
    _partialTranscript = '';
    _notifyStateChanged();
  }

  Future<void> _handleIncomingMessage(SpeechMessage message) async {
    await _playIncomingMessage(message.copyWith(origin: MessageOrigin.remote));
    _notifyStateChanged();
  }

  Future<void> _playIncomingMessage(SpeechMessage message) async {
    _history.insert(0, message);
    _rememberMessage(message);
    _benchmarkTracker.mark(message.id, BenchmarkEvent.t4MessageReceived);

    await _nativeBridgeService.speakText(
      text: message.message,
      emergency: message.type == MessageType.emergency,
      languageCode: message.languageCode,
      messageId: message.id,
    );

    _recordBenchmark(
      _benchmarkTracker.snapshotFor(
        message.id,
        audioDuration: _estimateAudioDuration(message.message),
      ),
    );

    _status = message.type == MessageType.emergency
        ? 'Emergency alert queued'
        : 'Message queued for playback';
  }

  Duration _estimateAudioDuration(String text) {
    final int wordCount = text
        .split(RegExp(r'\s+'))
        .where((String token) => token.trim().isNotEmpty)
        .length;
    final int estimatedMs = (wordCount * 350).clamp(500, 15000).toInt();
    return Duration(milliseconds: estimatedMs);
  }

  String _newMessageId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  SpeechMessage? _lookupMessage(String messageId) {
    final SpeechMessage? cached = _messageById[messageId];
    if (cached != null) {
      return cached;
    }

    for (final SpeechMessage message in _history) {
      if (message.id == messageId) {
        _messageById[messageId] = message;
        return message;
      }
    }

    return null;
  }

  void _rememberMessage(SpeechMessage message) {
    _messageById[message.id] = message;
  }
}
