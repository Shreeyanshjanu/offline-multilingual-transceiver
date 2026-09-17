import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/gps_location.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';

class _FakeGpsNativeBridge extends NativeBridgeService {
  GpsLocation? fakeLocation = const GpsLocation(
    latitude: 28.6139,
    longitude: 77.2090,
    altitude: 216.0,
    accuracy: 4.5,
  );

  @override
  Future<void> initialize({required String languageCode}) async {}

  @override
  Future<String?> getAppDataDirectoryPath() async => null;

  @override
  Future<GpsLocation?> getCurrentLocation() async => fakeLocation;

  @override
  Future<void> startLocationUpdates() async {}

  @override
  Future<void> stopLocationUpdates() async {}

  @override
  Future<void> speakText({
    required String text,
    required bool emergency,
    required String languageCode,
    required String messageId,
  }) async {}
}

class _MemoryUserProfileStorage extends UserProfileStorageService {
  UserProfile? _profile;

  @override
  Future<UserProfile?> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      _profile;

  @override
  Future<void> save(
      {required UserProfile profile,
      required Future<String?> Function() appDataPathProvider}) async {
    _profile = profile;
  }

  @override
  Future<void> clear(
      {required Future<String?> Function() appDataPathProvider}) async {
    _profile = null;
  }
}

void main() {
  group('GpsLocation model', () {
    test('formats coordinates correctly for North-East hemisphere', () {
      const GpsLocation loc = GpsLocation(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracy: 4.0,
      );

      expect(loc.formattedCoordinates, '28.6139° N, 77.2090° E');
      expect(loc.compactCoordinates, '28.6139, 77.2090');
      expect(loc.accuracyLabel, '±4m');
    });

    test('formats coordinates correctly for South-West hemisphere', () {
      const GpsLocation loc = GpsLocation(
        latitude: -33.8688,
        longitude: -151.2093,
      );

      expect(loc.formattedCoordinates, '33.8688° S, 151.2093° W');
      expect(loc.compactCoordinates, '-33.8688, -151.2093');
      expect(loc.accuracyLabel, '');
    });

    test('round-trips through JSON', () {
      const GpsLocation loc = GpsLocation(
        latitude: 19.0760,
        longitude: 72.8777,
        altitude: 14.5,
        accuracy: 3.0,
        provider: 'gps',
      );

      final Map<String, dynamic> json = loc.toJson();
      expect(json['lat'], 19.0760);
      expect(json['lng'], 72.8777);
      expect(json['alt'], 14.5);
      expect(json['acc'], 3.0);
      expect(json['provider'], 'gps');

      final GpsLocation restored = GpsLocation.fromJson(json);
      expect(restored.latitude, 19.0760);
      expect(restored.longitude, 72.8777);
      expect(restored.altitude, 14.5);
      expect(restored.accuracy, 3.0);
      expect(restored.provider, 'gps');
    });
  });

  group('UserProfile model', () {
    test('initial profile has correct defaults', () {
      const UserProfile profile = UserProfile.initial;
      expect(profile.callsign, 'Operator-1');
      expect(profile.role, 'Field Operator');
      expect(profile.squad, 'Alpha Squad');
      expect(profile.shareLocation, true);
      expect(profile.isConfigured, false);
    });

    test('round-trips through JSON', () {
      const UserProfile profile = UserProfile(
        callsign: 'Bravo-6',
        role: 'Medic',
        squad: 'Rescue Unit 4',
        notes: 'Blood type O+',
        shareLocation: false,
        isConfigured: true,
      );

      final Map<String, dynamic> json = profile.toJson();
      final UserProfile restored = UserProfile.fromJson(json);

      expect(restored.callsign, 'Bravo-6');
      expect(restored.role, 'Medic');
      expect(restored.squad, 'Rescue Unit 4');
      expect(restored.notes, 'Blood type O+');
      expect(restored.shareLocation, false);
      expect(restored.isConfigured, true);
    });
  });

  group('SpeechMessage wire payload with sender and GPS location', () {
    test('serializes sender and location to network JSON', () {
      final SpeechMessage msg = SpeechMessage(
        id: '12345',
        type: MessageType.speech,
        languageCode: 'hi',
        message: 'Checkpoint Alpha cleared',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        origin: MessageOrigin.local,
        senderCallsign: 'Falcon-1',
        senderRole: 'Squad Leader',
        senderSquad: 'Strike Team',
        location: const GpsLocation(
          latitude: 26.9124,
          longitude: 75.7873,
          accuracy: 5.0,
        ),
      );

      final Map<String, dynamic> wire = msg.toJsonNetwork();

      expect(wire['id'], '12345');
      expect(wire['type'], 'speech');
      expect(wire['language'], 'hi');
      expect(wire['message'], 'Checkpoint Alpha cleared');
      expect(wire['sender']['callsign'], 'Falcon-1');
      expect(wire['sender']['role'], 'Squad Leader');
      expect(wire['sender']['squad'], 'Strike Team');
      expect(wire['location']['lat'], 26.9124);
      expect(wire['location']['lng'], 75.7873);
      expect(wire['location']['acc'], 5.0);
    });

    test(
        'deserializes legacy wire format without sender or location gracefully',
        () {
      final Map<String, dynamic> legacyWire = <String, dynamic>{
        'id': '99999',
        'type': 'speech',
        'language': 'en',
        'message': 'Legacy transceiver voice packet',
        'timestamp': 1700000000000,
      };

      final SpeechMessage parsed = SpeechMessage.fromJson(legacyWire);

      expect(parsed.id, '99999');
      expect(parsed.message, 'Legacy transceiver voice packet');
      expect(parsed.senderCallsign, isNull);
      expect(parsed.senderRole, isNull);
      expect(parsed.location, isNull);
    });

    test('deserializes nested sender and location format accurately', () {
      final Map<String, dynamic> newWire = <String, dynamic>{
        'id': '88888',
        'type': 'emergency',
        'language': 'ta',
        'message': 'Immediate evacuation needed',
        'timestamp': 1700000000000,
        'sender': <String, dynamic>{
          'callsign': 'Medic-2',
          'role': 'Medic',
          'squad': 'Bravo Unit',
        },
        'location': <String, dynamic>{
          'lat': 13.0827,
          'lng': 80.2707,
          'alt': 12.0,
          'acc': 2.5,
        },
      };

      final SpeechMessage parsed = SpeechMessage.fromJson(newWire);

      expect(parsed.type, MessageType.emergency);
      expect(parsed.senderCallsign, 'Medic-2');
      expect(parsed.senderRole, 'Medic');
      expect(parsed.senderSquad, 'Bravo Unit');
      expect(parsed.location, isNotNull);
      expect(parsed.location!.latitude, 13.0827);
      expect(parsed.location!.longitude, 80.2707);
      expect(parsed.location!.accuracy, 2.5);
    });
  });

  group('UserProfileStorageService', () {
    late Directory tempDir;
    late UserProfileStorageService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('profile_test_');
      service = UserProfileStorageService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves and reloads user profile atomically', () async {
      Future<String?> dirProvider() async => tempDir.path;

      final UserProfile? initial =
          await service.load(appDataPathProvider: dirProvider);
      expect(initial, isNull);

      const UserProfile profile = UserProfile(
        callsign: 'Tanishq',
        role: 'Search & Rescue',
        squad: 'SIH Relief Force',
        shareLocation: true,
        isConfigured: true,
      );

      await service.save(profile: profile, appDataPathProvider: dirProvider);

      final UserProfile? loaded =
          await service.load(appDataPathProvider: dirProvider);
      expect(loaded, isNotNull);
      expect(loaded!.callsign, 'Tanishq');
      expect(loaded.role, 'Search & Rescue');
      expect(loaded.squad, 'SIH Relief Force');
      expect(loaded.isConfigured, true);

      await service.clear(appDataPathProvider: dirProvider);
      final UserProfile? cleared =
          await service.load(appDataPathProvider: dirProvider);
      expect(cleared, isNull);
    });
  });

  group('AppController with UserProfile & GPS', () {
    test('outgoing message attaches operator profile and GPS coordinates',
        () async {
      final _FakeGpsNativeBridge bridge = _FakeGpsNativeBridge();
      final AppController controller = AppController(
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );

      await controller.initialize();

      // Configure operator profile
      await controller.saveUserProfile(
        const UserProfile(
          callsign: 'Delta-1',
          role: 'Scout',
          squad: 'Frontline Unit',
          shareLocation: true,
          isConfigured: true,
        ),
      );

      await controller.sendTypedMessage('Approaching coordinates');

      expect(controller.history.isNotEmpty, true);
      final SpeechMessage sent = controller.history.first;
      expect(sent.senderCallsign, 'Delta-1');
      expect(sent.senderRole, 'Scout');
      expect(sent.senderSquad, 'Frontline Unit');
      expect(sent.location, isNotNull);
      expect(sent.location!.latitude, 28.6139);
      expect(sent.location!.longitude, 77.2090);

      controller.dispose();
    });

    test('location is withheld when shareLocation is disabled', () async {
      final _FakeGpsNativeBridge bridge = _FakeGpsNativeBridge();
      final AppController controller = AppController(
        nativeBridgeService: bridge,
        userProfileStorageService: _MemoryUserProfileStorage(),
      );

      await controller.initialize();

      await controller.saveUserProfile(
        const UserProfile(
          callsign: 'Ghost-9',
          role: 'Comms Officer',
          shareLocation: false,
          isConfigured: true,
        ),
      );

      await controller.sendTypedMessage('Radio check, silent mode');

      final SpeechMessage sent = controller.history.first;
      expect(sent.senderCallsign, 'Ghost-9');
      expect(sent.location, isNull);

      // Even a GPS fix obtained for local display must not leak into SOS text.
      await controller.refreshLocation();
      await controller.sendEmergencyPreset();
      expect(controller.history.first.location, isNull);
      expect(controller.history.first.message, isNot(contains('[GPS:')));

      controller.dispose();
    });
  });
}
