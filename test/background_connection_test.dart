import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/benchmark_models.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/benchmark_history_storage_service.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/tcp_message_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';
import 'package:sih_voice_bridge/app/theme/app_theme.dart';
import 'package:sih_voice_bridge/app/ui/widgets/settings/background_connection_card.dart';

class _Tcp extends TcpMessageService {
  bool active = false;
  int starts = 0, sends = 0;
  @override
  bool get isActive => active;
  @override
  bool get isConnected => active;
  @override
  Future<void> startServer({required int port}) async {
    starts++;
    active = true;
  }

  @override
  Future<void> send(SpeechMessage message) async {
    sends++;
  }

  @override
  Future<void> close() async {
    active = false;
  }
}

class _Bridge extends NativeBridgeService {
  _Bridge(this.tcp);
  final _Tcp tcp;
  final bus = StreamController<NativeEvent>.broadcast(sync: true);
  final Map<String, dynamic> status = {
    'backgroundEnabled': false,
    'connectionRequested': false,
    'serviceRunning': false,
    'connected': false,
    'state': 'disconnected',
    'generation': 0,
    'revision': 0,
    'runAsServer': true,
    'port': 7070,
    'host': '',
    'notificationsAllowed': false
  };
  final List<Map<String, dynamic>> records = [];
  int starts = 0, stops = 0, sends = 0, speaks = 0;
  Completer<bool>? permission;
  @override
  Stream<NativeEvent> get events => bus.stream;
  @override
  Future<void> initialize({required String languageCode}) async {}
  @override
  Future<String?> getAppDataDirectoryPath() async => null;
  @override
  Future<void> startLocationUpdates() async {}
  @override
  Future<void> stopLocationUpdates() async {}
  @override
  Future<Map<dynamic, dynamic>?> getBackgroundConnectionStatus() async {
    status['revision'] = (status['revision'] as int) + 1;
    return Map.of(status);
  }

  @override
  Future<Map<dynamic, dynamic>> setBackgroundConnectionEnabled(
      bool enabled) async {
    status['backgroundEnabled'] = enabled;
    if (!enabled) await stopBackgroundConnection();
    return (await getBackgroundConnectionStatus())!;
  }

  @override
  Future<bool> requestConnectionNotifications() async =>
      permission == null ? false : await permission!.future;
  @override
  Future<Map<dynamic, dynamic>> startBackgroundConnection(
      {required bool runAsServer,
      required String host,
      required int port,
      required String languageCode}) async {
    expect(tcp.active, isFalse,
        reason: 'Flutter socket must close before native starts');
    starts++;
    status.addAll({
      'generation': (status['generation'] as int) + 1,
      'serviceRunning': true,
      'connectionRequested': true,
      'connected': true,
      'state': 'connected',
      'host': host
    });
    return (await getBackgroundConnectionStatus())!;
  }

  @override
  Future<Map<dynamic, dynamic>> stopBackgroundConnection() async {
    stops++;
    status.addAll({
      'generation': (status['generation'] as int) + 1,
      'serviceRunning': false,
      'connectionRequested': false,
      'connected': false,
      'state': 'disconnected'
    });
    return (await getBackgroundConnectionStatus())!;
  }

  @override
  Future<void> sendBackgroundMessage(Map<String, dynamic> message) async {
    sends++;
  }

  @override
  Future<List<dynamic>> getBackgroundMessages() async => records;
  @override
  Future<void> acknowledgeBackgroundMessages(List<String> ids) async {}
  @override
  Future<void> clearBackgroundMessages() async {
    records.clear();
  }

  @override
  Future<void> speakText(
      {required String text,
      required bool emergency,
      required String languageCode,
      required String messageId}) async {
    speaks++;
  }

  void emit(Map<String, dynamic> event) => bus.add(NativeEvent.fromMap(event));
  @override
  Future<void> dispose() async {
    await bus.close();
  }
}

class _Profiles extends UserProfileStorageService {
  @override
  Future<UserProfile?> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      const UserProfile(
          callsign: 'Test',
          role: 'Medic',
          shareLocation: false,
          isConfigured: true);
}

class _History extends BenchmarkHistoryStorageService {
  @override
  Future<PersistedBenchmarkHistory> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      const PersistedBenchmarkHistory(snapshots: [], messagesById: {});
  @override
  Future<void> save(
      {required List<BenchmarkSnapshot> snapshots,
      required SpeechMessage? Function(String) messageLookup,
      required Future<String?> Function() appDataPathProvider}) async {}
}

AppController _controller(_Bridge bridge) => AppController(
    nativeBridgeService: bridge,
    tcpMessageService: bridge.tcp,
    userProfileStorageService: _Profiles(),
    benchmarkHistoryStorageService: _History());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('background OFF preserves Dart connection and send ownership', () async {
    final bridge = _Bridge(_Tcp());
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.connect();
    await controller.sendTypedMessage('Local test');
    expect(bridge.tcp.starts, 1);
    expect(bridge.tcp.sends, 1);
    expect(bridge.starts, 0);
  });
  test(
      'enabling while connected hands off exactly once despite notification denial',
      () async {
    final bridge = _Bridge(_Tcp());
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.connect();
    await controller.setBackgroundConnectionEnabled(true);
    await controller.sendTypedMessage('Native test');
    expect(bridge.starts, 1);
    expect(bridge.tcp.active, isFalse);
    expect(bridge.sends, 1);
    expect(bridge.tcp.sends, 0);
    expect(controller.backgroundConnection.serviceRunning, isTrue);
    await controller.connect();
    expect(bridge.starts, 1);
  });
  test(
      'reopen restores service and journal without reconnecting or replaying TTS',
      () async {
    final bridge = _Bridge(_Tcp());
    bridge.status.addAll({
      'backgroundEnabled': true,
      'serviceRunning': true,
      'connectionRequested': true,
      'connected': true,
      'state': 'connected'
    });
    final record = <String, dynamic>{
      'wire': {
        'id': 'remote-1',
        'message': 'Stored test',
        'language': 'en',
        'timestamp': 1000
      },
      'origin': 'remote',
      'receivedAt': 1000,
      'tts_started': 1010,
      'audio_started': 1020
    };
    bridge.records.add(record);
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    bridge.emit({'type': 'incoming_message', 'record': record});
    await controller.refreshBackgroundConnection();
    expect(controller.history.length, 1);
    expect(bridge.speaks, 0);
    expect(bridge.starts, 0);
    expect(bridge.tcp.starts, 0);
    expect(controller.isConnected, isTrue);
    expect(controller.latestBenchmark!.marks.t6AudioFirstFrame,
        DateTime.fromMillisecondsSinceEpoch(1020));
  });
  test(
      'manual disconnect cancels a connection waiting for notification permission',
      () async {
    final bridge = _Bridge(_Tcp());
    bridge.status['backgroundEnabled'] = true;
    bridge.permission = Completer<bool>();
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    final connecting = controller.connect();
    await Future<void>.delayed(Duration.zero);
    await controller.disconnect();
    bridge.permission!.complete(false);
    await connecting;
    expect(bridge.starts, 0);
    expect(bridge.status['connectionRequested'], isFalse);
    expect(controller.isNetworkActive, isFalse);
  });
  test('stale native status cannot undo manual disconnect', () async {
    final bridge = _Bridge(_Tcp());
    bridge.status['backgroundEnabled'] = true;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.connect();
    final stale = Map<String, dynamic>.of(bridge.status);
    await controller.disconnect();
    bridge.emit({'type': 'connection_state', ...stale});
    expect(controller.isConnected, isFalse);
    expect(controller.backgroundConnection.connectionRequested, isFalse);
  });
  test(
      'turning background OFF stops service and preserves foreground reconnect',
      () async {
    final bridge = _Bridge(_Tcp());
    bridge.status['backgroundEnabled'] = true;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.connect();
    await controller.setBackgroundConnectionEnabled(false);
    expect(controller.backgroundConnection.enabled, isFalse);
    expect(controller.isNetworkActive, isFalse);
    await controller.connect();
    expect(bridge.tcp.starts, 1);
    expect(bridge.starts, 1);
  });
  test('native disable event clears connected state without a UI command',
      () async {
    final bridge = _Bridge(_Tcp());
    bridge.status['backgroundEnabled'] = true;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.connect();
    expect(controller.isConnected, isTrue);
    final stopped = await bridge.setBackgroundConnectionEnabled(false);
    bridge.emit(
        {'type': 'connection_state', ...Map<String, dynamic>.from(stopped)});
    expect(controller.isConnected, isFalse);
    expect(controller.isNetworkActive, isFalse);
  });
  testWidgets('background setting fits a narrow display at large text scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bridge = _Bridge(_Tcp());
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
                child: SingleChildScrollView(
                    child:
                        BackgroundConnectionCard(controller: controller))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Keep Connection Active in Background'), findsOneWidget);
  });
}
