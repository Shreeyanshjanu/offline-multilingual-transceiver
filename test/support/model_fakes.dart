import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sih_voice_bridge/app/services/model_catalog_service.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';

final class TestCatalog extends ModelCatalogService {
  TestCatalog() {
    for (final code in ['en', 'hi', 'gu']) {
      final model = utf8.encode('verified weights for $code');
      final tokens =
          utf8.encode(code == 'en' ? 'English tokens' : 'shared Indic tokens');
      files['stt-$code-model.int8.onnx'] = model;
      final tokenName =
          code == 'en' ? 'stt-en-tokens.txt' : 'stt-indic-tokens.txt';
      files[tokenName] = tokens;
      models[code] = SttModelInfo(
          languageCode: code,
          type: 'nemo_ctc',
          modelFile: 'stt-$code-model.int8.onnx',
          modelUrl: 'https://example.invalid/$code',
          tokensFile: tokenName,
          tokensUrl: 'https://example.invalid/$tokenName',
          modelSizeBytes: model.length,
          modelSha256: sha256.convert(model).toString(),
          tokensSizeBytes: tokens.length,
          tokensSha256: sha256.convert(tokens).toString());
    }
  }
  final Map<String, List<int>> files = {};
  final Map<String, SttModelInfo> models = {};
  @override
  Future<Map<String, SttModelInfo>> load() async => models;
}

class TestDownloadBridge extends NativeBridgeService {
  TestDownloadBridge(this.root, this.catalog);
  final Directory root;
  final TestCatalog catalog;
  final Map<String, Map<String, dynamic>> states = {};
  final Map<String, int> starts = {};
  final List<String> cancelled = [];
  final List<String> startOrder = [];
  bool hold = false;
  bool corrupt = false;
  int _nextId = 1;

  Future<void> complete(String key, String name) async {
    final File file = File('${root.path}/external/$name');
    await file.parent.create(recursive: true);
    final bytes = List<int>.from(catalog.files[name]!);
    if (corrupt) bytes[0] = bytes[0] ^ 1;
    await file.writeAsBytes(bytes);
    states[key] = {
      'downloadId': states[key]?['downloadId'] ?? _nextId++,
      'status': 'successful',
      'bytesDownloaded': bytes.length,
      'totalBytes': bytes.length,
      'localUri': file.uri.toString(),
    };
  }

  Future<int> _start(String key, String name) async {
    if (states.containsKey(key)) return states[key]!['downloadId'] as int;
    starts[key] = (starts[key] ?? 0) + 1;
    startOrder.add(key);
    states[key] = {
      'downloadId': _nextId++,
      'status': 'running',
      'bytesDownloaded': 40,
      'totalBytes': 100
    };
    if (!hold) await complete(key, name);
    return states[key]!['downloadId'] as int;
  }

  @override
  Future<int?> startModelDownload(
          {required String languageCode,
          required String modelUrl,
          required String modelFileName}) =>
      _start(languageCode, modelFileName);
  @override
  Future<int?> startTokenDownload(
          {required String key,
          required String tokensUrl,
          required String tokensFileName}) =>
      _start('tokens_$key', tokensFileName);
  @override
  Future<Map<dynamic, dynamic>?> getModelDownloadStatus(String code) async =>
      states[code];
  @override
  Future<Map<dynamic, dynamic>?> getTokenDownloadStatus(String key) async =>
      states['tokens_$key'];
  @override
  Future<void> cancelModelDownload(String code) async {
    cancelled.add(code);
    states.remove(code);
  }

  @override
  Future<void> cancelTokenDownload(String key) async {
    cancelled.add('tokens_$key');
    states.remove('tokens_$key');
  }

  @override
  Future<String?> getAppDataDirectoryPath() async => root.path;
}

Future<void> writeInternal(
    Directory root, String relative, List<int> bytes) async {
  final file = File('${root.path}/stt_models/$relative');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
