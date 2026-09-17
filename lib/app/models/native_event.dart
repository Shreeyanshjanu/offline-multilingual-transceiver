enum NativeEventType {
  connectionState,
  incomingMessage,
  connectionError,
  partial,
  finalSentence,
  ttsStarted,
  audioStarted,
  resourceMetrics,
  captureState,
  sttReady,
  sttMetrics,
  captureMetrics,
  modelLoading,
  modelReady,
  status,
  error,
}

NativeEventType nativeEventTypeFromWire(String rawType) {
  switch (rawType) {
    case 'connection_state':
      return NativeEventType.connectionState;
    case 'incoming_message':
      return NativeEventType.incomingMessage;
    case 'connection_error':
      return NativeEventType.connectionError;
    case 'partial':
      return NativeEventType.partial;

    case 'final_sentence':
      return NativeEventType.finalSentence;

    case 'tts_started':
      return NativeEventType.ttsStarted;

    case 'audio_started':
      return NativeEventType.audioStarted;

    case 'resource_metrics':
      return NativeEventType.resourceMetrics;

    case 'capture_state':
      return NativeEventType.captureState;

    case 'stt_ready':
      return NativeEventType.sttReady;

    case 'stt_metrics':
      return NativeEventType.sttMetrics;

    case 'capture_metrics':
      return NativeEventType.captureMetrics;
    case 'model_loading':
      return NativeEventType.modelLoading;
    case 'model_ready':
      return NativeEventType.modelReady;
    case 'error':
      return NativeEventType.error;

    default:
      return NativeEventType.status;
  }
}

class NativeEvent {
  NativeEvent({
    required this.type,
    this.text,
    this.messageId,
    this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final NativeEventType type;
  final String? text;
  final String? messageId;
  final Map<dynamic, dynamic>? payload;
  final DateTime timestamp;

  factory NativeEvent.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    final String rawType = (raw['type'] ?? 'status').toString();

    return NativeEvent(
      type: nativeEventTypeFromWire(rawType),
      text: raw['text']?.toString(),
      messageId: raw['messageId']?.toString(),
      payload: raw,
      timestamp: raw['timestampEpochMs'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (raw['timestampEpochMs'] as num).toInt(),
            )
          : DateTime.now(),
    );
  }
}
