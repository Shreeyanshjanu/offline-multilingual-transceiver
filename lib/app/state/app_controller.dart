import 'dart:async';

import 'package:flutter/material.dart';

import '../models/benchmark_models.dart';
import '../models/background_connection_status.dart';
import '../models/connection_config.dart';
import '../models/gps_location.dart';
import '../models/language_option.dart';
import '../models/operation_mode.dart';
import '../models/speech_message.dart';
import '../models/user_profile.dart';
import '../services/benchmark_export_service.dart';
import '../services/benchmark_history_storage_service.dart';
import '../services/benchmark_tracker.dart';
import '../services/native_bridge_service.dart';
import '../services/tcp_message_service.dart';
import '../services/user_profile_storage_service.dart';

part 'app_controller_messages.dart';
part 'app_controller_events.dart';
part 'app_controller_benchmarks.dart';
part 'app_controller_connection.dart';

class AppController extends ChangeNotifier {
  static const int _maxBenchmarkHistory = 50;

  AppController({
    NativeBridgeService? nativeBridgeService,
    this.ownsNativeBridge = true,
    Iterable<String>? availableLanguageCodes,
    TcpMessageService? tcpMessageService,
    BenchmarkTracker? benchmarkTracker,
    BenchmarkExportService? benchmarkExportService,
    BenchmarkHistoryStorageService? benchmarkHistoryStorageService,
    UserProfileStorageService? userProfileStorageService,
  })  : _availableLanguageCodes =
            Set.unmodifiable(availableLanguageCodes ?? ['en']),
        _nativeBridgeService = nativeBridgeService ?? NativeBridgeService(),
        _tcpMessageService = tcpMessageService ?? TcpMessageService(),
        _benchmarkTracker = benchmarkTracker ?? BenchmarkTracker(),
        _benchmarkExportService =
            benchmarkExportService ?? const BenchmarkExportService(),
        _benchmarkHistoryStorageService =
            benchmarkHistoryStorageService ?? BenchmarkHistoryStorageService(),
        _userProfileStorageService =
            userProfileStorageService ?? UserProfileStorageService();

  final NativeBridgeService _nativeBridgeService;
  final bool ownsNativeBridge;
  final Set<String> _availableLanguageCodes;
  List<LanguageOption> get availableLanguages => kLanguageOptions
      .where((language) => _availableLanguageCodes.contains(language.code))
      .toList();
  final TcpMessageService _tcpMessageService;
  final BenchmarkTracker _benchmarkTracker;
  final BenchmarkExportService _benchmarkExportService;
  final BenchmarkHistoryStorageService _benchmarkHistoryStorageService;
  final UserProfileStorageService _userProfileStorageService;

  StreamSubscription<NativeEvent>? _nativeEventsSub;
  bool _initialized = false;
  bool _disposed = false;
  bool _connectionBusy = false;
  int _connectionCommand = 0;
  bool _usingNativeConnection = false;
  bool _messagesVisible = false;
  final Set<String> _nativeMessageIds = <String>{};
  BackgroundConnectionStatus _backgroundConnection =
      const BackgroundConnectionStatus();

  BackgroundConnectionStatus get backgroundConnection => _backgroundConnection;
  bool get connectionBusy => _connectionBusy;
  String get connectionStateLabel => _usingNativeConnection
      ? _backgroundConnection.state.toUpperCase()
      : _isConnected
          ? 'CONNECTED'
          : _connectionBusy
              ? 'CONNECTING'
              : 'DISCONNECTED';

  Future<void> setBackgroundConnectionEnabled(bool enabled) =>
      _setBackgroundEnabled(enabled);
  Future<void> openConnectionBatterySettings() =>
      _nativeBridgeService.openConnectionBatterySettings();
  Future<void> refreshBackgroundConnection() async {
    await _restoreBackgroundConnection();
    await _restoreBackgroundMessages();
  }

  void setMessagesVisible(bool visible) {
    _messagesVisible = visible;
    if (visible) {
      unawaited(_acknowledgeNativeMessages(_nativeMessageIds.toList()));
    }
  }

  bool _isConnected = false;
  bool _isListening = false;
  bool _capturePending = false;
  bool _stopRequested = false;
  bool? _sttReady;
  Map<String, dynamic> _latestSttMetrics = <String, dynamic>{};
  Map<String, dynamic> _latestCaptureMetrics = <String, dynamic>{};
  String _status = 'Booting...';
  String _partialTranscript = '';
  OperationMode _operationMode = OperationMode.walkieTalkie;
  LanguageOption _selectedLanguage = kLanguageOptions.first;
  ConnectionConfig _connectionConfig = ConnectionConfig.initial;
  final List<SpeechMessage> _history = <SpeechMessage>[];
  final List<BenchmarkSnapshot> _benchmarkHistory = <BenchmarkSnapshot>[];
  final Map<String, SpeechMessage> _messageById = <String, SpeechMessage>{};
  BenchmarkSnapshot? _latestBenchmark;
  String? _activeMessageId;
  UserProfile _userProfile = UserProfile.initial;
  GpsLocation? _currentLocation;
  bool _profileSetupNeeded = false;
  String _sttModelName = 'NeMo CTC int8 (EN)';
  String _ttsModelName = 'Android System TTS (en-US)';
  bool _isModelLoading = false;
  String? _modelLoadingMessage;
  bool _emergencyVolumeBoostEnabled = true;

  bool get isConnected => _isConnected;
  bool get isNetworkActive => _usingNativeConnection
      ? _backgroundConnection.connectionRequested ||
          _backgroundConnection.serviceRunning ||
          _backgroundConnection.startPending
      : _tcpMessageService.isActive;
  bool get isListening => _isListening;
  bool get isCapturePending => _capturePending;
  Map<String, dynamic> get latestSttMetrics =>
      Map<String, dynamic>.unmodifiable(_latestSttMetrics);
  Map<String, dynamic> get latestCaptureMetrics =>
      Map<String, dynamic>.unmodifiable(_latestCaptureMetrics);
  String get status => _status;
  String get partialTranscript => _partialTranscript;
  OperationMode get operationMode => _operationMode;
  LanguageOption get selectedLanguage => _selectedLanguage;
  ConnectionConfig get connectionConfig => _connectionConfig;
  UserProfile get userProfile => _userProfile;
  GpsLocation? get currentLocation => _currentLocation;
  bool get profileSetupNeeded => _profileSetupNeeded;
  String get sttModelName => _sttModelName;
  String get ttsModelName => _ttsModelName;
  bool get isModelLoading => _isModelLoading;
  bool get isSttReady => _sttReady == true;
  String? get modelLoadingMessage => _modelLoadingMessage;
  bool get emergencyVolumeBoostEnabled => _emergencyVolumeBoostEnabled;
  List<SpeechMessage> get history => List<SpeechMessage>.unmodifiable(_history);

  @visibleForTesting
  void addTestMessage(SpeechMessage message) {
    _history.insert(0, message);
    notifyListeners();
  }

  List<BenchmarkSnapshot> get benchmarkHistory =>
      List<BenchmarkSnapshot>.unmodifiable(_benchmarkHistory);
  BenchmarkSnapshot? get latestBenchmark => _latestBenchmark;
  ResourceBenchmark get resourceBenchmark =>
      _benchmarkTracker.resourceBenchmark;

  Future<void> initialize({
    String? initialLanguageCode,
  }) async {
    if (_initialized) {
      return;
    }

    _tcpMessageService.onMessage = _handleIncomingMessage;
    _tcpMessageService.onConnectionChanged = (bool connected) {
      _isConnected = connected;
      notifyListeners();
    };
    _tcpMessageService.onStatus = (String status) {
      _status = status;
      notifyListeners();
    };

    _nativeEventsSub = _nativeBridgeService.events.listen(_handleNativeEvent);

    await _restoreBackgroundConnection(restoreConfig: true);
    final String languageCode = _backgroundConnection.languageCode ??
        initialLanguageCode ??
        _selectedLanguage.code;

    _selectedLanguage = availableLanguages.firstWhere(
      (LanguageOption language) => language.code == languageCode,
      orElse: () => availableLanguages.first,
    );

    await _nativeBridgeService.initialize(
      languageCode: _selectedLanguage.code,
    );

    final UserProfile? persistedProfile = await _userProfileStorageService.load(
      appDataPathProvider: _nativeBridgeService.getAppDataDirectoryPath,
    );
    if (persistedProfile != null && persistedProfile.isConfigured) {
      _userProfile = persistedProfile;
      _profileSetupNeeded = false;
    } else {
      _profileSetupNeeded = true;
    }

    if (_userProfile.shareLocation) {
      await _nativeBridgeService.startLocationUpdates();
      _currentLocation = await _nativeBridgeService.getCurrentLocation();
    }

    final PersistedBenchmarkHistory persistedHistory =
        await _benchmarkHistoryStorageService.load(
      appDataPathProvider: _nativeBridgeService.getAppDataDirectoryPath,
    );

    _restorePersistedBenchmarkHistory(persistedHistory);
    await refreshBackgroundConnection();

    _status = !_nativeBridgeService.nativeAvailable
        ? 'Native speech unavailable; typed messaging remains available'
        : _sttReady == false
            ? 'Offline STT unavailable; typed messaging remains available'
            : _sttReady == true
                ? 'Ready'
                : 'Preparing offline speech recognition...';

    _initialized = true;
    notifyListeners();
  }

  void updateConnectionConfig(ConnectionConfig config) {
    _connectionConfig = config;
    notifyListeners();
  }

  /// Automatically retrieves the active Wi-Fi Gateway / Hotspot Leader IP
  /// from the native platform and populates client connection settings.
  Future<String?> fetchWifiGatewayIp() async {
    final String? gateway = await _nativeBridgeService.getWifiGatewayIp();
    if (gateway != null && gateway.isNotEmpty) {
      updateConnectionConfig(
        _connectionConfig.copyWith(
          host: gateway,
          runAsServer: false,
        ),
      );
      return gateway;
    }
    return null;
  }

  Future<void> connect() => _connectConfigured();

  Future<void> disconnect() => _disconnectConfigured();

  Future<void> setLanguage(LanguageOption language) async {
    if (!_availableLanguageCodes.contains(language.code)) {
      _status = '${language.label} model is not downloaded';
      notifyListeners();
      return;
    }
    _selectedLanguage = language;
    _sttReady = null;
    _isModelLoading = true;
    _modelLoadingMessage =
        'Loading ${language.label} speech model... Please wait 1-2s';
    _sttModelName = 'NeMo CTC (${language.code.toUpperCase()})';
    _ttsModelName = 'Android System TTS (${language.code})';
    _status = 'Loading ${language.label} model...';
    notifyListeners();

    try {
      await _nativeBridgeService.setLanguage(language.code);
    } catch (error) {
      _isModelLoading = false;
      _modelLoadingMessage = null;
      _sttReady = false;
      _status = 'Language switch failed: $error';
      notifyListeners();
    }
  }

  Future<void> setOperationMode(OperationMode mode) async {
    _operationMode = mode;
    await _nativeBridgeService.setOperationMode(mode);
    _status = mode == OperationMode.walkieTalkie
        ? 'Walkie-talkie mode'
        : 'Continuous mode';
    notifyListeners();
  }

  Future<void> startPushToTalk() async {
    final DateTime pressedAt = DateTime.now();
    if (_capturePending) {
      return;
    }
    if (_isModelLoading) {
      _status = 'Speech model is loading. Please wait 1-2 seconds...';
      notifyListeners();
      return;
    }
    if (_sttReady == false) {
      _status = 'Offline STT unavailable; no fallback transcript will be sent';
      notifyListeners();
      return;
    }

    final String messageId = _newMessageId();
    _activeMessageId = messageId;
    _capturePending = true;
    _stopRequested = false;
    _isListening = false;
    _partialTranscript = '';
    _status = 'Starting microphone... wait for Listening';
    _benchmarkTracker.mark(messageId, BenchmarkEvent.t0SpeechStart,
        at: pressedAt);

    notifyListeners();
    final bool accepted = await _nativeBridgeService.startListening(
      ptt: _operationMode == OperationMode.walkieTalkie,
      languageCode: _selectedLanguage.code,
      messageId: messageId,
      pressedAtEpochMs: pressedAt.millisecondsSinceEpoch,
    );
    if (!accepted && _activeMessageId == messageId) {
      _capturePending = false;
      _activeMessageId = null;
      _status = 'Could not start native speech capture';
    }
    notifyListeners();
  }

  Future<void> stopPushToTalk() async {
    if (!_capturePending || _stopRequested) {
      return;
    }

    _isListening = false;
    _stopRequested = true;
    _status = 'Finishing captured audio and recognizing speech...';
    notifyListeners();
    await _nativeBridgeService.stopListening();
  }

  Future<double?> getPlaybackVolume() =>
      _nativeBridgeService.getPlaybackVolume();

  Future<double?> setPlaybackVolume(double percent) =>
      _nativeBridgeService.setPlaybackVolume(percent);

  Future<void> setEmergencyVolumeBoost(bool enabled) async {
    if (await _nativeBridgeService.setEmergencyVolumeBoost(enabled)) {
      _emergencyVolumeBoostEnabled = enabled;
      notifyListeners();
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final UserProfile updated = profile.copyWith(isConfigured: true);
    await _userProfileStorageService.save(
      profile: updated,
      appDataPathProvider: _nativeBridgeService.getAppDataDirectoryPath,
    );
    _userProfile = updated;
    _profileSetupNeeded = false;
    if (updated.shareLocation) {
      await refreshLocation(requestPermission: true);
    } else {
      await _nativeBridgeService.stopLocationUpdates();
      _currentLocation = null;
    }
    notifyListeners();
  }

  Future<void> refreshLocation({bool requestPermission = false}) async {
    try {
      if (requestPermission &&
          !await _nativeBridgeService.hasLocationPermission() &&
          !await _nativeBridgeService.requestLocationPermission()) {
        _status = 'Location permission not granted';
        notifyListeners();
        return;
      }
      await _nativeBridgeService.startLocationUpdates();
      final GpsLocation? loc = await _nativeBridgeService.getCurrentLocation();
      if (loc != null) {
        _currentLocation = loc;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> sendTypedMessage(String text, {bool emergency = false}) async {
    final String cleaned = text.trim();
    if (cleaned.isEmpty) {
      return;
    }

    final String messageId = _newMessageId();
    _benchmarkTracker
      ..mark(messageId, BenchmarkEvent.t0SpeechStart)
      ..mark(messageId, BenchmarkEvent.t1SpeechEnd)
      ..mark(messageId, BenchmarkEvent.t2SttFinal);

    final SpeechMessage message = SpeechMessage(
      id: messageId,
      type: emergency ? MessageType.emergency : MessageType.speech,
      languageCode: _selectedLanguage.code,
      message: cleaned,
      timestamp: DateTime.now(),
      origin: MessageOrigin.local,
      senderCallsign: _userProfile.callsign,
      senderRole: _userProfile.role,
      senderSquad: _userProfile.squad,
      location: _userProfile.shareLocation ? _currentLocation : null,
    );

    await _sendOutgoingMessage(message);
  }

  Future<void> sendEmergencyPreset() {
    final String locStr = _userProfile.shareLocation && _currentLocation != null
        ? ' [GPS: ${_currentLocation!.compactCoordinates}]'
        : '';
    final String callsign = _userProfile.callsign;
    final String role = _userProfile.role;

    final String messageText = switch (_selectedLanguage.code.toLowerCase()) {
      'mr' => '$callsign ($role) साठी वैद्यकीय मदत आवश्यक आहे$locStr',
      'hi' => '$callsign ($role) के लिए चिकित्सा सहायता आवश्यक है$locStr',
      'gu' => '$callsign ($role) માટે તબીબી સહાય જરૂરી છે$locStr',
      'ta' => '$callsign ($role) க்கு மருத்துவ உதவி தேவை$locStr',
      'te' => '$callsign ($role) కొరకు వైద్య సహాయం అవసరం$locStr',
      'kn' => '$callsign ($role) ಗೆ ವೈದ್ಯಕೀಯ ನೆರವು ಅಗತ್ಯವಿದೆ$locStr',
      'ml' => '$callsign ($role) ന് അടിയന്തര വൈദ്യസഹായം ആവശ്യമാണ്$locStr',
      'bn' => '$callsign ($role) এর জন্য জরুরি চিকিৎসা সহায়তা প্রয়োজন$locStr',
      'or' => '$callsign ($role) ପାଇଁ ଡାକ୍ତରୀ ସହାୟତା ଆବଶ୍ୟକ$locStr',
      _ => 'Medical assistance required for $callsign ($role)$locStr',
    };

    return sendTypedMessage(messageText, emergency: true);
  }

  void clearHistory() {
    final Set<String> messageIds = <String>{
      ..._history.map((SpeechMessage message) => message.id),
      ..._benchmarkHistory
          .map((BenchmarkSnapshot snapshot) => snapshot.messageId),
    };
    for (final String messageId in messageIds) {
      _benchmarkTracker.clear(messageId);
    }

    if (_backgroundConnection.supported) {
      unawaited(
          _nativeBridgeService.clearBackgroundMessages().catchError((Object _) {
        if (!_disposed) {
          _status = 'Could not clear background history';
          _notifyStateChanged();
        }
      }));
    }
    _history.clear();
    _benchmarkHistory.clear();
    _messageById.clear();
    _latestBenchmark = null;
    unawaited(
      _benchmarkHistoryStorageService.clear(
        appDataPathProvider: _nativeBridgeService.getAppDataDirectoryPath,
      ),
    );
    notifyListeners();
  }

  String? exportLatestBenchmarkAsJson() {
    final BenchmarkSnapshot? snapshot = _latestBenchmark;
    if (snapshot == null) {
      return null;
    }

    return _benchmarkExportService.toJson(
      snapshot: snapshot,
      resource: _benchmarkTracker.resourceBenchmark,
      message: _lookupMessage(snapshot.messageId),
    );
  }

  String? exportLatestBenchmarkAsCsv() {
    final BenchmarkSnapshot? snapshot = _latestBenchmark;
    if (snapshot == null) {
      return null;
    }

    return _benchmarkExportService.toCsv(
      snapshot: snapshot,
      resource: _benchmarkTracker.resourceBenchmark,
      message: _lookupMessage(snapshot.messageId),
    );
  }

  String? exportBenchmarkHistoryAsJson({int? limit}) {
    if (_benchmarkHistory.isEmpty) {
      return null;
    }

    return _benchmarkExportService.historyToJson(
      snapshots: _benchmarkHistory,
      limit: limit,
      messageLookup: _lookupMessage,
    );
  }

  String? exportBenchmarkHistoryAsCsv({int? limit}) {
    if (_benchmarkHistory.isEmpty) {
      return null;
    }

    return _benchmarkExportService.historyToCsv(
      snapshots: _benchmarkHistory,
      limit: limit,
      messageLookup: _lookupMessage,
    );
  }

  // Keep ChangeNotifier notifications inside the owning class.
  void _notifyStateChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_connectionCommand;
    final StreamSubscription<NativeEvent>? nativeEventsSub = _nativeEventsSub;
    if (nativeEventsSub != null) {
      unawaited(nativeEventsSub.cancel());
    }
    unawaited(_nativeBridgeService.stopLocationUpdates());
    _tcpMessageService.onStatus = null;
    _tcpMessageService.onConnectionChanged = null;
    _tcpMessageService.onMessage = null;
    if (ownsNativeBridge) unawaited(_nativeBridgeService.dispose());
    unawaited(_tcpMessageService.close());
    super.dispose();
  }
}
