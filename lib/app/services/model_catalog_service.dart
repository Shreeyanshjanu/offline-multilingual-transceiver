import 'dart:convert';

import 'package:flutter/services.dart';

class SttModelInfo {
  const SttModelInfo({
    required this.languageCode,
    required this.type,
    required this.modelFile,
    required this.modelUrl,
    required this.tokensFile,
    required this.tokensUrl,
    required this.modelSizeBytes,
    required this.modelSha256,
    required this.tokensSizeBytes,
    required this.tokensSha256,
  });

  final String languageCode;
  final String type;
  final String modelFile;
  final String modelUrl;
  final String tokensFile;
  final String tokensUrl;
  final int modelSizeBytes;
  final String modelSha256;
  final int tokensSizeBytes;
  final String tokensSha256;

  bool get isIndic => languageCode != 'en';

  factory SttModelInfo.fromJson(
    String languageCode,
    Map<String, dynamic> json,
  ) {
    return SttModelInfo(
      languageCode: languageCode,
      type: json['type'] as String? ?? 'nemo_ctc',
      modelFile: json['modelFile'] as String,
      modelUrl: json['modelUrl'] as String,
      tokensFile: json['tokensFile'] as String,
      tokensUrl: json['tokensUrl'] as String,
      modelSizeBytes: json['modelSizeBytes'] as int,
      modelSha256: json['modelSha256'] as String,
      tokensSizeBytes: json['tokensSizeBytes'] as int,
      tokensSha256: json['tokensSha256'] as String,
    );
  }
}

class ModelCatalogService {
  static const String _manifestPath = 'assets/models/stt/model_manifest.json';

  Map<String, SttModelInfo>? _cache;

  Future<Map<String, SttModelInfo>> load() async {
    if (_cache != null) {
      return _cache!;
    }

    final String rawManifest = await rootBundle.loadString(_manifestPath);

    final Map<String, dynamic> root =
        jsonDecode(rawManifest) as Map<String, dynamic>;

    final Map<String, dynamic> languages =
        root['languages'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final Map<String, SttModelInfo> catalog = <String, SttModelInfo>{};

    for (final MapEntry<String, dynamic> entry in languages.entries) {
      final Map<String, dynamic> languageData =
          Map<String, dynamic>.from(entry.value as Map);

      catalog[entry.key] = SttModelInfo.fromJson(
        entry.key,
        languageData,
      );
    }

    if (catalog.isEmpty) {
      throw StateError('No STT models found in model manifest.');
    }

    _cache = Map.unmodifiable(catalog);
    return _cache!;
  }

  Future<SttModelInfo> get(String languageCode) async {
    final Map<String, SttModelInfo> catalog = await load();

    final SttModelInfo? model = catalog[languageCode.toLowerCase()];

    if (model == null) {
      throw StateError(
        'No STT model configuration found for "$languageCode".',
      );
    }

    return model;
  }
}
