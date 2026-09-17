import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_catalog_service.dart';
import 'model_download_service.dart';
import 'native_bridge_service.dart';

class ModelManager extends ChangeNotifier {
  ModelManager({
    required Future<String?> Function() appDataDirectoryPath,
    required NativeBridgeService nativeBridgeService,
    ModelCatalogService? catalogService,
    ModelDownloadService? downloadService,
    Future<SharedPreferences> Function()? preferencesProvider,
  })  : _catalog = catalogService ?? ModelCatalogService(),
        _preferences = preferencesProvider ?? SharedPreferences.getInstance {
    _downloads = downloadService ??
        ModelDownloadService(
          appDataDirectoryPath: appDataDirectoryPath,
          nativeBridgeService: nativeBridgeService,
          catalogService: _catalog,
        );
  }

  static const int maxSelectedLanguages = 2;
  static const String selectionKey = 'selected_languages';
  static const String pendingKey = 'language_setup_pending';
  static const String completeKey = 'language_setup_complete';

  final ModelCatalogService _catalog;
  final Future<SharedPreferences> Function() _preferences;
  late final ModelDownloadService _downloads;
  final List<String> _downloaded = [];
  final Map<String, ModelDownloadProgress> _progress = {};
  List<String> _selected = ['en'];
  Future<void>? _refreshFuture;
  Future<void>? _batch;
  bool _initialized = false;
  bool _disposed = false;
  bool _pending = false;
  bool _complete = false;
  String? _activeLanguage;
  String? _error;

  List<String> get downloadedLanguages => List.unmodifiable(_downloaded);
  List<String> get selectedLanguages => List.unmodifiable(_selected);
  bool get isInitialized => _initialized;
  bool get isDownloading => _batch != null;
  bool get hasPendingSetup => _pending;
  bool get setupComplete => _complete;
  String? get activeLanguage => _activeLanguage;
  String? get error => _error;
  Map<String, double> get progress => Map.unmodifiable(
      _progress.map((code, value) => MapEntry(code, value.progress)));
  double progressFor(String code) => _progress[code]?.progress ?? 0;
  String statusFor(String code) =>
      _progress[code]?.status ?? 'Preparing download';
  bool isDownloaded(String code) => _downloaded.contains(code.toLowerCase());

  // Coalesce overlapping scans, but refresh again on every later resume.
  Future<void> initialize() {
    _checkActive();
    return _refreshFuture ??=
        (isDownloading && _initialized ? _refreshProgress() : _refresh())
            .whenComplete(() => _refreshFuture = null);
  }

  Future<void> _refreshProgress() async {
    // The active batch owns the installed list. A resume scan must not replace
    // that list with a snapshot taken before a model finished downloading.
    for (final String code in _selected) {
      final ModelDownloadProgress? state =
          await _downloads.currentProgress(code);
      if (state != null) _progress[code] = state;
    }
    _notify();
  }

  Future<void> _refresh() async {
    final SharedPreferences prefs = await _preferences();
    final Map<String, SttModelInfo> catalog = await _catalog.load();
    final List<String> downloaded = await _downloads.getDownloadedLanguages();
    _checkActive();
    _downloaded
      ..clear()
      ..addAll(downloaded);
    _selected = (prefs.getStringList(selectionKey) ??
            (downloaded.isEmpty ? ['en'] : downloaded))
        .where(catalog.containsKey)
        .toSet()
        .take(maxSelectedLanguages)
        .toList();
    if (_selected.isEmpty) _selected = ['en'];
    _pending = prefs.getBool(pendingKey) ?? false;
    _complete =
        (prefs.getBool(completeKey) ?? false) && _selected.every(isDownloaded);
    for (final String code in _selected) {
      final ModelDownloadProgress? state =
          await _downloads.currentProgress(code);
      if (state != null) _progress[code] = state;
    }
    if (!isDownloading && _pending) {
      _activeLanguage =
          _selected.where((code) => !isDownloaded(code)).firstOrNull;
    }
    _initialized = true;
    _notify();
  }

  Future<void> downloadSelection(List<String> languages) {
    _checkActive();
    return _batch ??= _downloadSelection(languages).whenComplete(() {
      _batch = null;
      _activeLanguage = null;
      _notify();
    });
  }

  Future<void> _downloadSelection(List<String> languages) async {
    try {
      final List<String> codes =
          languages.map((code) => code.toLowerCase()).toSet().toList();
      if (codes.isEmpty || codes.length > maxSelectedLanguages) {
        throw StateError('Select one or two languages.');
      }
      final Map<String, SttModelInfo> catalog = await _catalog.load();
      if (!codes.every(catalog.containsKey)) {
        throw StateError('Unknown language selected.');
      }
      await initialize();
      _selected = codes;
      _pending = true;
      _complete = false;
      _error = null;
      final SharedPreferences prefs = await _preferences();
      // Persist the full ordered queue before starting any native transfer.
      await prefs.setStringList(selectionKey, codes);
      await prefs.setBool(pendingKey, true);
      await prefs.setBool(completeKey, false);
      _checkActive();
      _notify();
      for (final String code in codes) {
        _checkActive();
        if (await _downloads.isModelDownloaded(code)) {
          if (!_downloaded.contains(code)) _downloaded.add(code);
          continue;
        }
        _downloaded.remove(code);
        if (_downloaded.length >= maxSelectedLanguages) {
          throw StateError(
              'Remove an unselected downloaded language before adding another.');
        }
        _activeLanguage = code;
        _notify();
        await _downloads.downloadModel(
          model: catalog[code]!,
          onProgress: (ModelDownloadProgress value) {
            _progress[code] = value;
            _notify();
          },
        );
        _checkActive();
        if (!await _downloads.isModelDownloaded(code)) {
          throw StateError(
              'Model and tokenizer verification did not complete.');
        }
        if (!_downloaded.contains(code)) _downloaded.add(code);
        _notify();
      }
    } catch (error) {
      _error = error.toString();
      rethrow;
    }
  }

  Future<void> markSetupComplete() async {
    if (!_selected.every(isDownloaded)) {
      throw StateError('Selected language files are not ready.');
    }
    final SharedPreferences prefs = await _preferences();
    await prefs.setBool(completeKey, true);
    await prefs.setBool(pendingKey, false);
    _pending = false;
    _complete = true;
    _notify();
  }

  Future<void> delete(String code) async {
    if (isDownloading) {
      throw StateError('Wait for the current download to finish.');
    }
    await _downloads.deleteModel(code);
    _downloaded.remove(code);
    _progress.remove(code);
    _complete = false;
    final SharedPreferences prefs = await _preferences();
    await prefs.setBool(completeKey, false);
    _notify();
  }

  Future<String?> getModelPath(String code) => _downloads.getModelPath(code);
  Future<String?> getTokensPath(String code) => _downloads.getTokensPath(code);
  Future<Map<String, SttModelInfo>> getCatalog() => _catalog.load();

  void _checkActive() {
    if (_disposed) throw StateError('Model manager disposed.');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _downloads.dispose();
    super.dispose();
  }
}
