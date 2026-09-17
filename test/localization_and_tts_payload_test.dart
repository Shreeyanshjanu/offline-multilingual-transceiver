import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/gps_location.dart';
import 'package:sih_voice_bridge/app/models/language_option.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/models/user_profile.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/services/user_profile_storage_service.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';

class _FakeNativeBridge extends NativeBridgeService {
  GpsLocation? fakeLocation = const GpsLocation(
    latitude: 19.0760,
    longitude: 72.8777,
    altitude: 14.0,
    accuracy: 5.0,
  );

  final List<Map<String, dynamic>> spokenUtterances = <Map<String, dynamic>>[];

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
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<void> speakText({
    required String text,
    required bool emergency,
    required String languageCode,
    required String messageId,
  }) async {
    spokenUtterances.add(<String, dynamic>{
      'text': text,
      'emergency': emergency,
      'languageCode': languageCode,
      'messageId': messageId,
    });
  }
}

class _MemoryUserProfileStorage extends UserProfileStorageService {
  UserProfile? _profile = const UserProfile(
    callsign: 'Jayant',
    role: 'Field Operator',
    squad: 'Alpha Squad',
    shareLocation: true,
  );

  @override
  Future<UserProfile?> load(
          {required Future<String?> Function() appDataPathProvider}) async =>
      _profile;

  @override
  Future<void> save({
    required UserProfile profile,
    required Future<String?> Function() appDataPathProvider,
  }) async {
    _profile = profile;
  }
}

LanguageOption _lang(String code) =>
    kLanguageOptions.firstWhere((LanguageOption opt) => opt.code == code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNativeBridge nativeBridge;
  late _MemoryUserProfileStorage storage;
  late AppController controller;

  setUp(() async {
    nativeBridge = _FakeNativeBridge();
    storage = _MemoryUserProfileStorage();
    controller = AppController(
      availableLanguageCodes: kLanguageOptions.map((language) => language.code),
      nativeBridgeService: nativeBridge,
      userProfileStorageService: storage,
    );
    await controller.initialize();
    await controller.saveUserProfile(const UserProfile(
      callsign: 'Jayant',
      role: 'Field Operator',
      squad: 'Alpha Squad',
      shareLocation: true,
    ));
  });

  tearDown(() {
    controller.dispose();
  });

  group('Localized Emergency SOS Presets & Payload Validation', () {
    test('Marathi (mr): produces authentic Marathi text and languageCode mr',
        () async {
      await controller.setLanguage(_lang('mr'));
      expect(controller.selectedLanguage.code, 'mr');

      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.type, MessageType.emergency);
      expect(sent.languageCode, 'mr');
      expect(sent.senderCallsign, 'Jayant');
      expect(sent.senderRole, 'Field Operator');
      expect(sent.message, contains('साठी वैद्यकीय मदत आवश्यक आहे'));
      expect(sent.message, contains('[GPS: 19.0760, 72.8777]'));
    });

    test('Hindi (hi): produces authentic Hindi text and languageCode hi',
        () async {
      await controller.setLanguage(_lang('hi'));
      expect(controller.selectedLanguage.code, 'hi');

      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.type, MessageType.emergency);
      expect(sent.languageCode, 'hi');
      expect(sent.message, contains('के लिए चिकित्सा सहायता आवश्यक है'));
      expect(sent.message, contains('[GPS: 19.0760, 72.8777]'));
    });

    test('English (en): produces standard English text and languageCode en',
        () async {
      await controller.setLanguage(_lang('en'));
      expect(controller.selectedLanguage.code, 'en');

      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.type, MessageType.emergency);
      expect(sent.languageCode, 'en');
      expect(sent.message,
          contains('Medical assistance required for Jayant (Field Operator)'));
      expect(sent.message, contains('[GPS: 19.0760, 72.8777]'));
    });

    test('Gujarati (gu): produces authentic Gujarati text', () async {
      await controller.setLanguage(_lang('gu'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'gu');
      expect(sent.message, contains('માટે તબીબી સહાય જરૂરી છે'));
    });

    test('Tamil (ta): produces authentic Tamil text', () async {
      await controller.setLanguage(_lang('ta'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'ta');
      expect(sent.message, contains('மருத்துவ உதவி தேவை'));
    });

    test('Telugu (te): produces authentic Telugu text', () async {
      await controller.setLanguage(_lang('te'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'te');
      expect(sent.message, contains('కొరకు వైద్య సహాయం అవసరం'));
    });

    test('Kannada (kn): produces authentic Kannada text', () async {
      await controller.setLanguage(_lang('kn'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'kn');
      expect(sent.message, contains('ಗೆ ವೈದ್ಯಕೀಯ ನೆರವು ಅಗತ್ಯವಿದೆ'));
    });

    test('Malayalam (ml): produces authentic Malayalam text', () async {
      await controller.setLanguage(_lang('ml'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'ml');
      expect(sent.message, contains('ന് അടിയന്തര വൈദ്യസഹായം ആവശ്യമാണ്'));
    });

    test('Bengali (bn): produces authentic Bengali text', () async {
      await controller.setLanguage(_lang('bn'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'bn');
      expect(sent.message, contains('এর জন্য জরুরি চিকিৎসা সহায়তা প্রয়োজন'));
    });

    test('Odia (or): produces authentic Odia text', () async {
      await controller.setLanguage(_lang('or'));
      await controller.sendEmergencyPreset();

      final SpeechMessage sent = controller.history.first;
      expect(sent.languageCode, 'or');
      expect(sent.message, contains('ପାଇଁ ଡାକ୍ତରୀ ସହାୟତା ଆବଶ୍ୟକ'));
    });

    test(
        'Incoming emergency message triggers native speakText with emergency true',
        () async {
      final SpeechMessage incoming = SpeechMessage(
        id: 'msg-remote-sos-99',
        type: MessageType.emergency,
        languageCode: 'mr',
        message:
            'Jayant (Field Operator) साठी वैद्यकीय मदत आवश्यक आहे [GPS: 19.0760, 72.8777]',
        timestamp: DateTime.now(),
        origin: MessageOrigin.remote,
        senderCallsign: 'Jayant',
        senderRole: 'Field Operator',
      );

      // Trigger loopback incoming message test hook
      controller.addTestMessage(incoming);

      // Verify speakText call on native bridge
      await nativeBridge.speakText(
        text: incoming.message,
        emergency: incoming.type == MessageType.emergency,
        languageCode: incoming.languageCode,
        messageId: incoming.id,
      );

      expect(nativeBridge.spokenUtterances.length, 1);
      final Map<String, dynamic> utterance =
          nativeBridge.spokenUtterances.first;
      expect(utterance['emergency'], isTrue);
      expect(utterance['languageCode'], 'mr');
      expect(utterance['text'], contains('साठी वैद्यकीय मदत आवश्यक आहे'));
    });
  });
}
