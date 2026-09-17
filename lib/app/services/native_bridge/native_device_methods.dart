part of '../native_bridge_service.dart';

mixin _NativeDeviceMethods {
  set _nativeAvailable(bool value);

  Future<double?> getPlaybackVolume() async {
    try {
      final num? result = await NativeBridgeService._methodChannel
          .invokeMethod<num>('getPlaybackVolume');
      return result?.toDouble().clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  Future<double?> setPlaybackVolume(double percent) async {
    try {
      final num? result =
          await NativeBridgeService._methodChannel.invokeMethod<num>(
        'setPlaybackVolume',
        <String, dynamic>{'percent': percent.clamp(0, 100)},
      );
      return result?.toDouble().clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getAppDataDirectoryPath() async {
    try {
      final String? path =
          await NativeBridgeService._methodChannel.invokeMethod<String>(
        'getAppDataDirectory',
      );

      if (path == null || path.trim().isEmpty) {
        return null;
      }

      return path.trim();
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<GpsLocation?> getCurrentLocation() async {
    try {
      final Object? raw = await NativeBridgeService._methodChannel
          .invokeMethod<dynamic>('getLocation');
      if (raw is Map) {
        return GpsLocation.fromJson(Map<String, dynamic>.from(raw));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasLocationPermission() async {
    try {
      final bool? res = await NativeBridgeService._methodChannel
          .invokeMethod<bool>('hasLocationPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestLocationPermission() async {
    try {
      return await NativeBridgeService._methodChannel
              .invokeMethod<bool>('requestLocationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> startLocationUpdates() async {
    try {
      await NativeBridgeService._methodChannel
          .invokeMethod<dynamic>('startLocationUpdates');
    } catch (_) {}
  }

  Future<void> stopLocationUpdates() async {
    try {
      await NativeBridgeService._methodChannel
          .invokeMethod<dynamic>('stopLocationUpdates');
    } catch (_) {}
  }

  Future<String?> getWifiGatewayIp() async {
    try {
      final String? ip = await NativeBridgeService._methodChannel
          .invokeMethod<String>('getWifiGatewayIp');
      if (ip != null && ip.trim().isNotEmpty && ip != '0.0.0.0') {
        return ip.trim();
      }
    } catch (_) {}

    // Pure Dart local network fallback when native channel is unavailable
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final NetworkInterface iface in interfaces) {
        final String name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('swlan')) {
          for (final InternetAddress addr in iface.addresses) {
            final List<String> parts = addr.address.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}.1';
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
