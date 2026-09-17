import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/gps_location.dart';
import '../models/native_event.dart';
import '../models/operation_mode.dart';

export '../models/native_event.dart';

part 'native_bridge/native_device_methods.dart';
part 'native_bridge/native_model_downloads.dart';
part 'native_bridge/native_connection_methods.dart';

class NativeBridgeService
    with _NativeDeviceMethods, _NativeModelDownloads, _NativeConnectionMethods {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.sih.voicebridge/native',
  );

  static const EventChannel _eventChannel = EventChannel(
    'com.sih.voicebridge/native_events',
  );

  final StreamController<NativeEvent> _eventsController =
      StreamController<NativeEvent>.broadcast();

  StreamSubscription<dynamic>? _nativeEventSubscription;

  bool _nativeAvailable = true;
  String? _activeMessageId;

  Stream<NativeEvent> get events => _eventsController.stream;

  bool get nativeAvailable => _nativeAvailable;

  Future<void> initialize({
    required String languageCode,
  }) async {
    await _subscribeToEventStream();

    await _invoke(
      'initializePipelines',
      <String, dynamic>{
        'languageCode': languageCode,
      },
    );
  }

  Future<void> setLanguage(
    String languageCode,
  ) async {
    await _invoke(
      'setLanguage',
      <String, dynamic>{
        'languageCode': languageCode,
      },
    );
  }

  Future<void> setOperationMode(
    OperationMode mode,
  ) async {
    await _invoke(
      'setOperationMode',
      <String, dynamic>{
        'mode': operationModeToWire(mode),
      },
    );
  }

  Future<bool> startListening({
    required bool ptt,
    required String languageCode,
    required String messageId,
    int? pressedAtEpochMs,
  }) async {
    _activeMessageId = messageId;

    return _invoke(
      'startListening',
      <String, dynamic>{
        'ptt': ptt,
        'languageCode': languageCode,
        'messageId': messageId,
        'pressedAtEpochMs':
            pressedAtEpochMs ?? DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> stopListening() async {
    await _invoke(
      'stopListening',
      <String, dynamic>{
        'messageId': _activeMessageId,
      },
    );
  }

  Future<void> speakText({
    required String text,
    required bool emergency,
    required String languageCode,
    required String messageId,
  }) async {
    await _invoke(
      'speakText',
      <String, dynamic>{
        'text': text,
        'emergency': emergency,
        'languageCode': languageCode,
        'messageId': messageId,
      },
    );
  }

  Future<void> setEmergencyOverride(
    bool enabled,
  ) async {
    await _invoke(
      'setEmergencyOverride',
      <String, dynamic>{
        'enabled': enabled,
      },
    );
  }

  Future<bool> setEmergencyVolumeBoost(bool enabled) =>
      _invoke('setEmergencyVolumeBoost', <String, dynamic>{'enabled': enabled});

  Future<bool> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _methodChannel.invokeMethod<void>(
        method,
        args,
      );

      return true;
    } on MissingPluginException {
      _nativeAvailable = false;

      _emitInvocationError(
        method,
        'Native pipeline unavailable; '
        'no recognition or playback was performed.',
      );

      return false;
    } on PlatformException catch (error) {
      _emitInvocationError(
        method,
        error.message ?? error.code,
      );

      return false;
    }
  }

  void _emitInvocationError(
    String method,
    String text,
  ) {
    if (_eventsController.isClosed) {
      return;
    }

    _eventsController.add(
      NativeEvent(
        type: NativeEventType.error,
        text: text,
        messageId: _activeMessageId,
        payload: <String, dynamic>{
          'operation': method,
          'captureId': _activeMessageId,
          'captureError':
              method == 'startListening' || method == 'stopListening',
        },
      ),
    );
  }

  Future<void> _subscribeToEventStream() async {
    if (_nativeEventSubscription != null) {
      return;
    }

    try {
      _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic payload) {
          if (payload is Map<dynamic, dynamic>) {
            if (payload['type'] == 'capture_state' &&
                payload['state'] == 'stopped' &&
                payload['captureId'] == _activeMessageId) {
              _activeMessageId = null;
            }

            _eventsController.add(
              NativeEvent.fromMap(payload),
            );
          }
        },
        onError: (Object error) {
          _eventsController.add(
            NativeEvent(
              type: NativeEventType.error,
              text: error.toString(),
              messageId: _activeMessageId,
            ),
          );
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
    }
  }

  Future<void> dispose() async {
    if (_activeMessageId != null) {
      await stopListening();
    }

    await _nativeEventSubscription?.cancel();
    await _eventsController.close();
  }
}
