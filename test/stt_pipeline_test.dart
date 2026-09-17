import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/benchmark_models.dart';
import 'package:sih_voice_bridge/app/models/connection_config.dart';
import 'package:sih_voice_bridge/app/models/language_option.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/benchmark_history_storage_service.dart';
import 'package:sih_voice_bridge/app/services/benchmark_tracker.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/tcp_message_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';

class _MemoryHistory extends BenchmarkHistoryStorageService {
  @override
  Future<PersistedBenchmarkHistory> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      const PersistedBenchmarkHistory(
          snapshots: <BenchmarkSnapshot>[],
          messagesById: <String, SpeechMessage>{});

  @override
  Future<void> save(
      {required List<BenchmarkSnapshot> snapshots,
      required SpeechMessage? Function(String messageId) messageLookup,
      required Future<String?> Function() appDataPathProvider}) async {}

  @override
  Future<void> clear(
      {required Future<String?> Function() appDataPathProvider}) async {}
}

class _FakeNativeBridge extends NativeBridgeService {
  final StreamController<NativeEvent> bus =
      StreamController<NativeEvent>.broadcast(sync: true);
  final List<({String text, bool emergency})> playback =
      <({String text, bool emergency})>[];
  String? activeId;
  int starts = 0;
  int stops = 0;
  final List<String> languages = [];
  bool sttAvailable = true;

  @override
  Stream<NativeEvent> get events => bus.stream;

  void emit(Map<String, dynamic> event) => bus.add(NativeEvent.fromMap(event));

  @override
  Future<void> initialize({required String languageCode}) async =>
      emit(<String, dynamic>{'type': 'stt_ready', 'available': sttAvailable});

  @override
  Future<String?> getAppDataDirectoryPath() async => null;

  @override
  Future<void> setLanguage(String languageCode) async {
    languages.add(languageCode);
    emit({'type': 'stt_ready', 'available': true});
  }

  @override
  Future<bool> startListening(
      {required bool ptt,
      required String languageCode,
      required String messageId,
      int? pressedAtEpochMs}) async {
    activeId = messageId;
    starts++;
    return true;
  }

  @override
  Future<void> stopListening() async {
    stops++;
  }

  void captureState(String state) => emit(<String, dynamic>{
        'type': 'capture_state',
        'state': state,
        'captureId': activeId,
        'messageId': activeId,
      });

  @override
  Future<void> speakText(
      {required String text,
      required bool emergency,
      required String languageCode,
      required String messageId}) async {
    playback.add((text: text, emergency: emergency));
    emit(<String, dynamic>{
      'type': 'tts_started',
      'messageId': messageId,
      'text': text
    });
    emit(<String, dynamic>{
      'type': 'audio_started',
      'messageId': messageId,
      'text': text
    });
  }

  @override
  Future<void> dispose() async {
    await bus.close();
    await super.dispose();
  }
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

AppController _controller(_FakeNativeBridge bridge, {TcpMessageService? tcp}) =>
    AppController(
      nativeBridgeService: bridge,
      tcpMessageService: tcp,
      benchmarkHistoryStorageService: _MemoryHistory(),
      userProfileStorageService: _MemoryUserProfileStorage(),
    );

Future<void> _waitFor(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for loopback delivery');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language selection exposes and accepts only installed models',
      () async {
    final bridge = _FakeNativeBridge();
    final controller = AppController(
      nativeBridgeService: bridge,
      benchmarkHistoryStorageService: _MemoryHistory(),
      availableLanguageCodes: ['en', 'hi'],
    );
    await controller.initialize(initialLanguageCode: 'hi');
    expect(controller.availableLanguages.map((language) => language.code),
        ['en', 'hi']);
    await controller.setLanguage(
        kLanguageOptions.firstWhere((language) => language.code == 'gu'));
    expect(controller.selectedLanguage.code, 'hi');
    expect(bridge.languages, isEmpty);
    await controller.setLanguage(kLanguageOptions.first);
    expect(bridge.languages, ['en']);
    controller.dispose();
  });

  test('initialization preserves an unavailable backend status', () async {
    final _FakeNativeBridge bridge = _FakeNativeBridge()..sttAvailable = false;
    final AppController controller = _controller(bridge);
    await controller.initialize();
    expect(controller.status, contains('unavailable'));
    await controller.startPushToTalk();
    expect(bridge.starts, 0);
    controller.dispose();
  });

  test(
      'release during startup is honored and late readiness cannot restart listening',
      () async {
    final _FakeNativeBridge bridge = _FakeNativeBridge();
    final AppController controller = _controller(bridge);
    await controller.initialize();
    await controller.startPushToTalk();
    expect(controller.isListening, isFalse);
    expect(controller.isCapturePending, isTrue);
    await controller.stopPushToTalk();
    expect(bridge.stops, 1);
    bridge.captureState('recording');
    expect(controller.isListening, isFalse);
    bridge.captureState('stopped');
    expect(controller.isCapturePending, isFalse);
    await controller.startPushToTalk();
    expect(bridge.starts, 2);
    bridge.captureState('recording');
    expect(controller.isListening, isTrue);
    bridge.captureState('stopped');
    controller.dispose();
  });

  test('fallback and invalid recognition never become voice messages',
      () async {
    final _FakeNativeBridge bridge = _FakeNativeBridge();
    final AppController controller = _controller(bridge);
    await controller.initialize();
    for (final Map<String, dynamic> flags in <Map<String, dynamic>>[
      <String, dynamic>{'fallback': true, 'recognitionValid': true},
      <String, dynamic>{'recognitionValid': false},
      <String, dynamic>{},
    ]) {
      bridge.emit(<String, dynamic>{
        'type': 'final_sentence',
        'text': 'Emergency assistance is required',
        ...flags
      });
    }
    expect(controller.history, isEmpty);
    expect(bridge.playback, isEmpty);
    bridge.emit(<String, dynamic>{
      'type': 'stt_ready',
      'available': false,
      'fallback': true
    });
    await controller.startPushToTalk();
    expect(bridge.starts, 0);
    await controller.sendTypedMessage('live wire', emergency: true);
    expect(bridge.playback.single, (text: 'live wire', emergency: true));
    controller.dispose();
  });

  test('actual sample timing survives later estimated-duration snapshots', () {
    final BenchmarkTracker tracker = BenchmarkTracker();
    tracker.recordAudioTiming('voice',
        audioDuration: const Duration(milliseconds: 200),
        processingDuration: const Duration(milliseconds: 50));
    final BenchmarkSnapshot snapshot = tracker.snapshotFor('voice',
        audioDuration: const Duration(seconds: 9),
        processingDuration: const Duration(seconds: 5));
    expect(snapshot.audioDuration, const Duration(milliseconds: 200));
    expect(snapshot.rtf, 0.25);
    tracker.clear('voice');
    expect(tracker.snapshotFor('voice').audioDuration, isNull);
  });

  test('native failures emit errors instead of synthetic speech or playback',
      () async {
    const MethodChannel channel = MethodChannel('com.sih.voicebridge/native');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel, (MethodCall call) async => throw MissingPluginException());
    final NativeBridgeService bridge = NativeBridgeService();
    final List<NativeEvent> received = <NativeEvent>[];
    final StreamSubscription<NativeEvent> subscription =
        bridge.events.listen(received.add);
    try {
      expect(
          await bridge.startListening(
              ptt: true, languageCode: 'en', messageId: 'unavailable'),
          isFalse);
      await bridge.stopListening();
      await bridge.speakText(
          text: 'fire',
          emergency: false,
          languageCode: 'en',
          messageId: 'unavailable');
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(
          received.every(
              (NativeEvent event) => event.type == NativeEventType.error),
          isTrue);
    } finally {
      await subscription.cancel();
      await bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
      'all four phrases traverse real TCP unchanged as typed and validated voice messages',
      () async {
    final TcpMessageService server = TcpMessageService();
    final TcpMessageService client = TcpMessageService();
    final _FakeNativeBridge senderBridge = _FakeNativeBridge();
    final _FakeNativeBridge receiverBridge = _FakeNativeBridge();
    final AppController sender = _controller(senderBridge, tcp: server);
    final AppController receiver = _controller(receiverBridge, tcp: client);
    try {
      await sender.initialize();
      await receiver.initialize();
      receiver.updateConnectionConfig(const ConnectionConfig(
          host: '127.0.0.1', port: 7070, runAsServer: false));
      await sender.connect();
      await receiver.connect();
      await _waitFor(() => server.isConnected);
      var delivered = 0;
      for (final String phrase in <String>[
        'fire',
        'wire',
        'live wire',
        'not a fire'
      ]) {
        await sender.sendTypedMessage(phrase);
        delivered++;
        await _waitFor(() => receiverBridge.playback.length == delivered);
        expect(receiverBridge.playback.last, (text: phrase, emergency: false));

        await sender.startPushToTalk();
        senderBridge.captureState('recording');
        await sender.stopPushToTalk();
        final int endedAt = DateTime.now().millisecondsSinceEpoch - 500;
        senderBridge.emit(<String, dynamic>{
          'type': 'stt_metrics',
          'messageId': senderBridge.activeId,
          'recognitionValid': true,
          'audioDurationMs': 200,
          'processingDurationMs': 50,
          'deliveredSamples': 3200,
          'decodeCalls': 1,
          'audioStartEpochMs': endedAt - 200,
          'audioEndEpochMs': endedAt,
          'recognitionFinishedEpochMs': endedAt + 50,
        });
        senderBridge.emit(<String, dynamic>{
          'type': 'final_sentence',
          'messageId': senderBridge.activeId,
          'text': phrase,
          'recognitionValid': true,
          'fallback': false,
          'languageCode': 'en',
        });
        senderBridge.captureState('stopped');
        delivered++;
        await _waitFor(() => receiverBridge.playback.length == delivered);
        expect(receiverBridge.playback.last, (text: phrase, emergency: false));
        expect(sender.latestBenchmark!.audioDuration,
            const Duration(milliseconds: 200));
        expect(sender.latestBenchmark!.rtf, 0.25);
        expect(sender.latestBenchmark!.marks.t2SttFinal,
            DateTime.fromMillisecondsSinceEpoch(endedAt + 50));
      }
      await sender.sendTypedMessage('live wire', emergency: true);
      delivered++;
      await _waitFor(() => receiverBridge.playback.length == delivered);
      expect(
          receiverBridge.playback.last, (text: 'live wire', emergency: true));
      expect(receiver.history.first.type, MessageType.emergency);
      await sender.sendEmergencyPreset();
      delivered++;
      await _waitFor(() => receiverBridge.playback.length == delivered);
      expect(receiverBridge.playback.last, (
        text: 'Medical assistance required for Operator-1 (Field Operator)',
        emergency: true
      ));
      expect(receiver.history.first.senderCallsign, 'Operator-1');
      await receiver.sendTypedMessage('reply');
      await _waitFor(() => senderBridge.playback.isNotEmpty);
      expect(senderBridge.playback.last.text, 'reply');
    } finally {
      await server.close();
      await client.close();
      sender.dispose();
      receiver.dispose();
    }
  });
}
