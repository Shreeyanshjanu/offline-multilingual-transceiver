import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/benchmark_models.dart';
import 'package:sih_voice_bridge/app/models/gps_location.dart';
import 'package:sih_voice_bridge/app/models/language_option.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/benchmark_history_storage_service.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/tcp_message_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';
import 'package:sih_voice_bridge/app/theme/app_theme.dart';
import 'package:sih_voice_bridge/app/ui/app_shell.dart';
import 'package:sih_voice_bridge/app/ui/widgets/language_picker_sheet.dart';
import 'package:sih_voice_bridge/app/ui/widgets/model_status_badge.dart';

class _Bridge extends NativeBridgeService {
  final bus = StreamController<NativeEvent>.broadcast(sync: true);
  bool failLanguageSwitch = false;
  @override
  Stream<NativeEvent> get events => bus.stream;
  @override
  Future<void> initialize({required String languageCode}) async {
    emit(
        {'type': 'stt_ready', 'available': true, 'languageCode': languageCode});
  }

  void emit(Map<String, dynamic> value) => bus.add(NativeEvent.fromMap(value));
  @override
  Future<void> setLanguage(String languageCode) async {
    if (failLanguageSwitch) throw StateError('Model unavailable');
  }

  @override
  Future<String?> getAppDataDirectoryPath() async => null;
  @override
  Future<void> startLocationUpdates() async {}
  @override
  Future<void> stopLocationUpdates() async {}
  @override
  Future<GpsLocation?> getCurrentLocation() async => null;
  @override
  Future<void> dispose() async {
    await bus.close();
    await super.dispose();
  }
}

class _ProfileStore extends UserProfileStorageService {
  @override
  Future<UserProfile?> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      const UserProfile(callsign: 'Test', role: 'Medic', isConfigured: true);
}

class _HistoryStore extends BenchmarkHistoryStorageService {
  @override
  Future<PersistedBenchmarkHistory> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      const PersistedBenchmarkHistory(
          snapshots: <BenchmarkSnapshot>[],
          messagesById: <String, SpeechMessage>{});
}

class _Host extends TcpMessageService {
  bool active = false;
  @override
  bool get isActive => active;
  @override
  Future<void> startServer({required int port}) async => active = true;
  @override
  Future<void> close() async => active = false;
}

AppController _controller(_Bridge bridge, {TcpMessageService? tcp}) =>
    AppController(
      nativeBridgeService: bridge,
      availableLanguageCodes: const ['en', 'hi'],
      tcpMessageService: tcp,
      userProfileStorageService: _ProfileStore(),
      benchmarkHistoryStorageService: _HistoryStore(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new language picker offers only the installed languages',
      (tester) async {
    final controller = _controller(_Bridge());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LanguagePickerSheet(controller: controller))));
    expect(find.text(kLanguageOptions.firstWhere((l) => l.code == 'en').label),
        findsOneWidget);
    expect(find.text(kLanguageOptions.firstWhere((l) => l.code == 'hi').label),
        findsOneWidget);
    expect(find.text(kLanguageOptions.firstWhere((l) => l.code == 'mr').label),
        findsNothing);
    expect(find.text('Downloaded speech model'), findsNWidgets(2));
  });

  testWidgets('new shell can disconnect a host before any peer joins',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _Host();
    final controller = _controller(_Bridge(), tcp: host);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.updateConnectionConfig(
        controller.connectionConfig.copyWith(runAsServer: true));
    await controller.connect();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.35)),
        child: child!,
      ),
      home: AppShell(controller: controller),
    ));
    await tester.pump();
    expect(controller.isConnected, isFalse);
    expect(find.text('Waiting for peers on port 7070'), findsOneWidget);
    await tester.tap(find.text('DISCONNECT'));
    await tester.pump();
    expect(host.active, isFalse);
    expect(find.text('START LEADER MESH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('model status ignores stale languages and clears failed switches',
      () async {
    final bridge = _Bridge();
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    final hindi = kLanguageOptions.firstWhere((l) => l.code == 'hi');
    await controller.setLanguage(hindi);
    bridge.emit(
        {'type': 'model_ready', 'languageCode': 'en', 'sttAvailable': true});
    bridge.emit({'type': 'stt_ready', 'languageCode': 'en', 'available': true});
    expect(controller.isModelLoading, isTrue);
    bridge.emit(
        {'type': 'model_ready', 'languageCode': 'hi', 'sttAvailable': true});
    expect(controller.isModelLoading, isFalse);
    bridge.failLanguageSwitch = true;
    await controller
        .setLanguage(kLanguageOptions.firstWhere((l) => l.code == 'en'));
    expect(controller.isModelLoading, isFalse);
    expect(controller.isSttReady, isFalse);
    expect(controller.status, contains('Language switch failed'));
  });

  testWidgets('model loading banner fits narrow screens with larger text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(_Bridge());
    addTearDown(controller.dispose);
    await controller
        .setLanguage(kLanguageOptions.firstWhere((l) => l.code == 'hi'));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.35)),
        child: child!,
      ),
      home: Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: ModelStatusBadge(controller: controller))),
    ));
    expect(find.text('MODEL LOADING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
