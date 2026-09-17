import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';

class _FakeGatewayNativeBridge extends NativeBridgeService {
  String? mockGatewayIp = '192.168.43.1';

  @override
  Future<void> initialize({required String languageCode}) async {}

  @override
  Future<String?> getAppDataDirectoryPath() async => null;

  @override
  Future<String?> getWifiGatewayIp() async => mockGatewayIp;
}

class _MemoryUserProfileStorage extends UserProfileStorageService {
  @override
  Future<UserProfile?> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      null;

  @override
  Future<void> save(
      {required UserProfile profile,
      required Future<String?> Function() appDataPathProvider}) async {}

  @override
  Future<void> clear(
      {required Future<String?> Function() appDataPathProvider}) async {}
}

void main() {
  group('AppController Wi-Fi Gateway Discovery', () {
    test('auto-fetches active Wi-Fi Gateway and sets client mode', () async {
      final _FakeGatewayNativeBridge bridge = _FakeGatewayNativeBridge();
      bridge.mockGatewayIp = '192.168.43.1';

      final AppController controller = AppController(
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );

      await controller.initialize();

      expect(controller.connectionConfig.runAsServer, isTrue);

      final String? detected = await controller.fetchWifiGatewayIp();

      expect(detected, '192.168.43.1');
      expect(controller.connectionConfig.host, '192.168.43.1');
      expect(controller.connectionConfig.runAsServer, isFalse);

      controller.dispose();
    });

    test('handles disconnected Wi-Fi gracefully when gateway is null',
        () async {
      final _FakeGatewayNativeBridge bridge = _FakeGatewayNativeBridge();
      bridge.mockGatewayIp = null;

      final AppController controller = AppController(
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );

      await controller.initialize();

      final String? detected = await controller.fetchWifiGatewayIp();

      expect(detected, isNull);
      // host remains unchanged (empty initial server host)
      expect(controller.connectionConfig.host, '');

      controller.dispose();
    });
  });
}
