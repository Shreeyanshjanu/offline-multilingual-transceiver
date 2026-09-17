part of '../native_bridge_service.dart';

mixin _NativeModelDownloads {
  set _nativeAvailable(bool value);

  Future<int?> startModelDownload({
    required String languageCode,
    required String modelUrl,
    required String modelFileName,
  }) async {
    try {
      return await NativeBridgeService._methodChannel.invokeMethod<int>(
        'startModelDownload',
        <String, dynamic>{
          'languageCode': languageCode,
          'modelUrl': modelUrl,
          'modelFileName': modelFileName,
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<dynamic, dynamic>?> getModelDownloadStatus(
    String languageCode,
  ) async {
    try {
      return await NativeBridgeService._methodChannel
          .invokeMethod<Map<dynamic, dynamic>>(
        'getModelDownloadStatus',
        <String, dynamic>{
          'languageCode': languageCode,
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> cancelModelDownload(
    String languageCode,
  ) async {
    try {
      await NativeBridgeService._methodChannel.invokeMethod<void>(
        'cancelModelDownload',
        <String, dynamic>{
          'languageCode': languageCode,
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
    }
  }

  Future<int?> startTokenDownload({
    required String key,
    required String tokensUrl,
    required String tokensFileName,
  }) async {
    try {
      return await NativeBridgeService._methodChannel.invokeMethod<int>(
        'startTokenDownload',
        <String, dynamic>{
          'key': key,
          'tokensUrl': tokensUrl,
          'tokensFileName': tokensFileName,
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<dynamic, dynamic>?> getTokenDownloadStatus(
    String key,
  ) async {
    try {
      return await NativeBridgeService._methodChannel
          .invokeMethod<Map<dynamic, dynamic>>(
        'getTokenDownloadStatus',
        <String, dynamic>{
          'key': key,
        },
      );
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> cancelTokenDownload(String key) async {
    await NativeBridgeService._methodChannel.invokeMethod<void>(
      'cancelTokenDownload',
      <String, dynamic>{'key': key},
    );
  }
}
