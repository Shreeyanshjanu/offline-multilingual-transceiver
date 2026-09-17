import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'model_catalog_service.dart';
import 'native_bridge_service.dart';

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.languageCode,
    required this.receivedBytes,
    required this.totalBytes,
    required this.progress,
    this.status = 'Downloading',
  });
  final String languageCode;
  final int receivedBytes;
  final int totalBytes;
  final double progress;
  final String status;
}

class _Artifact {
  _Artifact(
      {required this.file,
      required this.size,
      required this.digest,
      required this.start,
      required this.query,
      required this.reset});
  final File file;
  final int size;
  final String digest;
  final Future<int?> Function() start;
  final Future<Map<dynamic, dynamic>?> Function() query;
  final Future<void> Function() reset;
}

Future<String> _fileDigest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

class ModelDownloadService {
  ModelDownloadService({
    required this.appDataDirectoryPath,
    required this.nativeBridgeService,
    ModelCatalogService? catalogService,
    this.pollInterval = const Duration(milliseconds: 700),
  }) : _catalog = catalogService ?? ModelCatalogService();

  final Future<String?> Function() appDataDirectoryPath;
  final NativeBridgeService nativeBridgeService;
  final ModelCatalogService _catalog;
  final Duration pollInterval;
  final Map<String, (int, DateTime, DateTime, String)> _verified = {};
  final Map<String, Future<bool>> _imports = {};
  bool _disposed = false;

  Future<_Artifact> _artifact(SttModelInfo model, {bool tokens = false}) async {
    final String? path = await appDataDirectoryPath();
    if (path == null || path.trim().isEmpty) {
      throw StateError('Unable to determine application data directory.');
    }
    final String root = '${path.trim()}/stt_models';
    final String code = model.languageCode;
    final String key = model.isIndic ? 'indic' : 'en';
    return _Artifact(
      file: File(tokens
          ? '$root/${model.tokensFile}'
          : '$root/$code/${model.modelFile}'),
      size: tokens ? model.tokensSizeBytes : model.modelSizeBytes,
      digest: tokens ? model.tokensSha256 : model.modelSha256,
      start: () => tokens
          ? nativeBridgeService.startTokenDownload(
              key: key,
              tokensUrl: model.tokensUrl,
              tokensFileName: model.tokensFile)
          : nativeBridgeService.startModelDownload(
              languageCode: code,
              modelUrl: model.modelUrl,
              modelFileName: model.modelFile),
      query: () => tokens
          ? nativeBridgeService.getTokenDownloadStatus(key)
          : nativeBridgeService.getModelDownloadStatus(code),
      reset: () => tokens
          ? nativeBridgeService.cancelTokenDownload(key)
          : nativeBridgeService.cancelModelDownload(code),
    );
  }

  Future<bool> _valid(File file, _Artifact artifact) async {
    final FileStat stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size != artifact.size) {
      _verified.remove(file.path);
      return false;
    }
    final signature = (stat.size, stat.modified, stat.changed, artifact.digest);
    if (_verified[file.path] == signature) return true;
    final String path = file.path;
    final String digest = await Isolate.run(() => _fileDigest(path));
    if (digest != artifact.digest) return false;
    _verified[path] = signature;
    return true;
  }

  // Refresh calls share imports and cannot overwrite each other's temporary file.
  Future<bool> _recover(_Artifact artifact) async {
    if (await _valid(artifact.file, artifact)) return true;
    final Map<dynamic, dynamic>? status = await artifact.query();
    if (status?['status'] != 'successful') return false;
    final Future<bool>? existing = _imports[artifact.file.path];
    if (existing != null) return existing;
    final Future<bool> work = _importCompleted(artifact, status!);
    _imports[artifact.file.path] = work;
    try {
      return await work;
    } finally {
      _imports.remove(artifact.file.path);
    }
  }

  Future<bool> _importCompleted(
      _Artifact artifact, Map<dynamic, dynamic> status) async {
    final Uri? uri = Uri.tryParse(status['localUri']?.toString() ?? '');
    if (uri == null || uri.scheme != 'file') {
      await artifact.reset();
      return false;
    }
    final File source = File.fromUri(uri);
    if (!await source.exists()) {
      await artifact.reset();
      return false;
    }
    final File temporary = File('${artifact.file.path}.part');
    await temporary.parent.create(recursive: true);
    try {
      await source.copy(temporary.path);
      if (!await _valid(temporary, artifact)) {
        await artifact.reset();
        throw StateError('Downloaded file failed verification. Please retry.');
      }
      _checkActive();
      // Same-directory rename publishes the entire verified file atomically.
      await temporary.rename(artifact.file.path);
      _verified.remove(artifact.file.path);
      return true;
    } finally {
      _verified.remove(temporary.path);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> isModelDownloaded(String languageCode) async {
    final SttModelInfo model = await _catalog.get(languageCode);
    return await _recover(await _artifact(model)) &&
        await _recover(await _artifact(model, tokens: true));
  }

  Future<List<String>> getDownloadedLanguages() async {
    final Map<String, SttModelInfo> catalog = await _catalog.load();
    final List<String> downloaded = [];
    for (final String code in catalog.keys) {
      _checkActive();
      if (await isModelDownloaded(code)) downloaded.add(code);
    }
    return downloaded;
  }

  Future<String?> getModelPath(String languageCode) async {
    if (!await isModelDownloaded(languageCode)) return null;
    return (await _artifact(await _catalog.get(languageCode))).file.path;
  }

  Future<String?> getTokensPath(String languageCode) async {
    final _Artifact tokens =
        await _artifact(await _catalog.get(languageCode), tokens: true);
    return await _recover(tokens) ? tokens.file.path : null;
  }

  Future<ModelDownloadProgress?> currentProgress(String languageCode) async {
    final SttModelInfo model = await _catalog.get(languageCode);
    final _Artifact weights = await _artifact(model);
    if (await _valid(weights.file, weights)) {
      final _Artifact tokens = await _artifact(model, tokens: true);
      if (await _valid(tokens.file, tokens)) {
        return ModelDownloadProgress(
            languageCode: languageCode,
            receivedBytes: 1,
            totalBytes: 1,
            progress: 1,
            status: 'Ready');
      }
      return _progress(languageCode, await tokens.query(), 0.99, 0.01);
    }
    return _progress(languageCode, await weights.query(), 0, 0.99);
  }

  ModelDownloadProgress? _progress(
    String code,
    Map<dynamic, dynamic>? state,
    double offset,
    double weight,
  ) {
    if (state == null) return null;
    final int received = (state['bytesDownloaded'] as num?)?.toInt() ?? 0;
    final int total = (state['totalBytes'] as num?)?.toInt() ?? 0;
    final double fraction = total > 0 ? (received / total).clamp(0, 1) : 0;
    final String status = switch (state['status']) {
      'successful' => 'Verifying download',
      'paused' => 'Waiting for Android to resume',
      'pending' => 'Waiting to download',
      'failed' => 'Download failed',
      _ => 'Downloading',
    };
    return ModelDownloadProgress(
        languageCode: code,
        receivedBytes: received,
        totalBytes: total,
        progress: (offset + fraction * weight).clamp(0, 0.999),
        status: status);
  }

  Future<void> downloadModel({
    required SttModelInfo model,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    _checkActive();
    await _downloadArtifact(
        await _artifact(model), model.languageCode, 0, 0.99, onProgress);
    await _downloadArtifact(await _artifact(model, tokens: true),
        model.languageCode, 0.99, 0.01, onProgress);
    onProgress?.call(ModelDownloadProgress(
        languageCode: model.languageCode,
        receivedBytes: 1,
        totalBytes: 1,
        progress: 1,
        status: 'Ready'));
  }

  Future<void> _downloadArtifact(
    _Artifact artifact,
    String code,
    double offset,
    double weight,
    void Function(ModelDownloadProgress)? onProgress,
  ) async {
    if (await _recover(artifact)) return;
    _checkActive();
    if (await artifact.start() == null) {
      throw StateError('Unable to start the Android download.');
    }
    while (true) {
      _checkActive();
      final Map<dynamic, dynamic>? status = await artifact.query();
      if (status == null) {
        throw StateError('Android download record is missing. Please retry.');
      }
      final ModelDownloadProgress? progress =
          _progress(code, status, offset, weight);
      if (progress != null) onProgress?.call(progress);
      switch (status['status']) {
        case 'successful':
          if (!await _recover(artifact)) {
            throw StateError('Downloaded file is missing. Please retry.');
          }
          return;
        case 'failed':
          await artifact.reset();
          throw StateError(
              'Android download failed (${status['reason']}). Please retry.');
        case 'pending':
        case 'running':
        case 'paused':
          await Future<void>.delayed(pollInterval);
        default:
          throw StateError(
              'Unknown Android download state: ${status['status']}');
      }
    }
  }

  Future<void> deleteModel(String languageCode) async {
    final _Artifact artifact =
        await _artifact(await _catalog.get(languageCode));
    await artifact.reset();
    if (await artifact.file.exists()) await artifact.file.delete();
    _verified.remove(artifact.file.path);
    // Shared tokenizers remain available to other installed languages.
  }

  void _checkActive() {
    if (_disposed) throw StateError('Download observer disposed.');
  }

  void dispose() {
    // Android keeps ownership of in-flight transfers.
    _disposed = true;
  }
}
