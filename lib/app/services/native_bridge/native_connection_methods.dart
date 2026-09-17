part of '../native_bridge_service.dart';

mixin _NativeConnectionMethods {
  Future<Map<dynamic, dynamic>?> getBackgroundConnectionStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      return await NativeBridgeService._methodChannel
          .invokeMapMethod<dynamic, dynamic>('getBackgroundConnectionStatus');
    } on MissingPluginException {
      return null;
    }
  }

  Future<Map<dynamic, dynamic>> setBackgroundConnectionEnabled(
          bool enabled) async =>
      await NativeBridgeService._methodChannel
          .invokeMapMethod<dynamic, dynamic>(
        'setBackgroundConnectionEnabled',
        <String, dynamic>{'enabled': enabled},
      ) ??
      <dynamic, dynamic>{};

  Future<Map<dynamic, dynamic>> startBackgroundConnection({
    required bool runAsServer,
    required String host,
    required int port,
    required String languageCode,
  }) async =>
      await NativeBridgeService._methodChannel
          .invokeMapMethod<dynamic, dynamic>(
        'startBackgroundConnection',
        <String, dynamic>{
          'runAsServer': runAsServer,
          'host': host,
          'port': port,
          'languageCode': languageCode
        },
      ) ??
      <dynamic, dynamic>{};

  Future<Map<dynamic, dynamic>> stopBackgroundConnection() async =>
      await NativeBridgeService._methodChannel
          .invokeMapMethod<dynamic, dynamic>('stopBackgroundConnection') ??
      <dynamic, dynamic>{};

  Future<void> sendBackgroundMessage(Map<String, dynamic> message) =>
      NativeBridgeService._methodChannel.invokeMethod<void>(
          'sendBackgroundMessage', <String, dynamic>{'message': message});

  Future<List<dynamic>> getBackgroundMessages() async =>
      await NativeBridgeService._methodChannel
          .invokeListMethod<dynamic>('getBackgroundMessages') ??
      <dynamic>[];

  Future<void> acknowledgeBackgroundMessages(List<String> ids) =>
      NativeBridgeService._methodChannel.invokeMethod<void>(
          'acknowledgeBackgroundMessages', <String, dynamic>{'ids': ids});

  Future<void> clearBackgroundMessages() => NativeBridgeService._methodChannel
      .invokeMethod<void>('clearBackgroundMessages');

  Future<bool> requestConnectionNotifications() async =>
      await NativeBridgeService._methodChannel
          .invokeMethod<bool>('requestConnectionNotifications') ??
      false;

  Future<void> openConnectionBatterySettings() =>
      NativeBridgeService._methodChannel
          .invokeMethod<void>('openConnectionBatterySettings');
}
