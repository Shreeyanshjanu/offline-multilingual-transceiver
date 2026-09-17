import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/gps_location.dart';
import 'package:sih_voice_bridge/app/models/language_option.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';
import 'package:sih_voice_bridge/app/ui/widgets/model_status_badge.dart';

class _FakeNativeBridgeWithStream extends NativeBridgeService {
  final StreamController<NativeEvent> _controller =
      StreamController<NativeEvent>.broadcast();

  @override
  Stream<NativeEvent> get events => _controller.stream;

  void emit(NativeEvent event) {
    _controller.add(event);
  }

  @override
  Future<void> initialize({required String languageCode}) async {}

  @override
  Future<String?> getAppDataDirectoryPath() async => null;

  @override
  Future<GpsLocation?> getCurrentLocation() async => null;

  @override
  Future<void> startLocationUpdates() async {}

  @override
  Future<void> stopLocationUpdates() async {}

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<bool> startListening({
    required bool ptt,
    required String languageCode,
    String? messageId,
    int? pressedAtEpochMs,
  }) async =>
      true;
}

class _MemoryUserProfileStorage extends UserProfileStorageService {
  final UserProfile _profile = const UserProfile(
    callsign: 'Tanishq',
    role: 'Field Operator',
    squad: 'Alpha Squad',
    shareLocation: true,
  );

  @override
  Future<UserProfile?> load(
          {Future<String?> Function()? appDataPathProvider}) async =>
      _profile;

  @override
  Future<void> save({
    required UserProfile profile,
    required Future<String?> Function() appDataPathProvider,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STT & TTS Model Status in AppController', () {
    test('Default model labels and idle loading state', () {
      final AppController controller = AppController();

      expect(controller.sttModelName, contains('NeMo CTC'));
      expect(controller.ttsModelName, contains('Android System TTS'));
      expect(controller.isModelLoading, isFalse);
      expect(controller.modelLoadingMessage, isNull);
    });

    test('setLanguage triggers isModelLoading and loading message', () async {
      final _FakeNativeBridgeWithStream bridge = _FakeNativeBridgeWithStream();
      final AppController controller = AppController(
        availableLanguageCodes: const ['en', 'hi', 'mr'],
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );
      await controller.initialize();

      final LanguageOption marathi =
          kLanguageOptions.firstWhere((LanguageOption l) => l.code == 'mr');
      final Future<void> switchFuture = controller.setLanguage(marathi);

      expect(controller.isModelLoading, isTrue);
      expect(controller.modelLoadingMessage, contains('Marathi'));
      expect(controller.modelLoadingMessage, contains('1-2s'));
      expect(controller.sttModelName, contains('MR'));
      expect(controller.ttsModelName, contains('mr'));

      await switchFuture;
    });

    test('startPushToTalk guards against recording while model is loading',
        () async {
      final _FakeNativeBridgeWithStream bridge = _FakeNativeBridgeWithStream();
      final AppController controller = AppController(
        availableLanguageCodes: const ['en', 'hi', 'mr'],
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );
      await controller.initialize();

      final LanguageOption marathi =
          kLanguageOptions.firstWhere((LanguageOption l) => l.code == 'mr');
      await controller.setLanguage(marathi);
      expect(controller.isModelLoading, isTrue);

      await controller.startPushToTalk();

      expect(controller.isListening, isFalse);
      expect(controller.isCapturePending, isFalse);
      expect(controller.status, contains('loading'));
      expect(controller.status, contains('1-2 seconds'));
    });

    test('NativeEventType.modelLoading and modelReady events update state',
        () async {
      final _FakeNativeBridgeWithStream bridge = _FakeNativeBridgeWithStream();
      final AppController controller = AppController(
        availableLanguageCodes: const ['en', 'hi', 'mr'],
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );
      await controller.initialize();

      // Emit modelLoading
      bridge.emit(
        NativeEvent(
          type: NativeEventType.modelLoading,
          text: 'Loading Hindi model... Please wait 1-2s',
          payload: <String, dynamic>{
            'sttModel': 'NeMo CTC int8 (HI)',
            'ttsModel': 'Android System TTS (hi-IN)',
            'isLoading': true,
            'message': 'Loading Hindi speech model... Please wait 1-2s',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.isModelLoading, isTrue);
      expect(controller.sttModelName, 'NeMo CTC int8 (HI)');
      expect(controller.ttsModelName, 'Android System TTS (hi-IN)');
      expect(controller.modelLoadingMessage, contains('Hindi'));

      // Emit modelReady
      bridge.emit(
        NativeEvent(
          type: NativeEventType.modelReady,
          text: 'Speech models active for HI',
          payload: <String, dynamic>{
            'sttModel': 'NeMo CTC int8 (HI)',
            'ttsModel': 'Android System TTS (hi-IN)',
            'sttAvailable': true,
            'isLoading': false,
            'message': 'Speech models active for HI',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.isModelLoading, isFalse);
      expect(controller.modelLoadingMessage, isNull);
      expect(controller.status, contains('HI'));
    });
  });

  group('ModelStatusBadge Widget Tests', () {
    testWidgets('renders ready chips when not loading',
        (WidgetTester tester) async {
      final AppController controller = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelStatusBadge(controller: controller),
          ),
        ),
      );

      expect(find.textContaining('STT:'), findsOneWidget);
      expect(find.textContaining('TTS:'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders loading banner with 1-2s wait notice when loading',
        (WidgetTester tester) async {
      final _FakeNativeBridgeWithStream bridge = _FakeNativeBridgeWithStream();
      final AppController controller = AppController(
        availableLanguageCodes: const ['en', 'hi', 'mr'],
        nativeBridgeService: bridge,
      );

      final LanguageOption marathi =
          kLanguageOptions.firstWhere((LanguageOption l) => l.code == 'mr');
      await controller.setLanguage(marathi);
      expect(controller.isModelLoading, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelStatusBadge(controller: controller),
          ),
        ),
      );

      expect(find.text('MODEL LOADING'), findsOneWidget);
      expect(find.text('• WAIT 1-2 SECONDS'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders without overflow on narrow 320px viewport',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final AppController controller = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ModelStatusBadge(controller: controller),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ModelStatusBadge), findsOneWidget);
    });
  });
}
