import 'dart:convert';
import 'dart:io';

import '../models/user_profile.dart';

class UserProfileStorageService {
  static const String _fileName = 'user_profile_v1.json';

  Future<UserProfile?> load({
    required Future<String?> Function() appDataPathProvider,
  }) async {
    final File file = await _resolveFile(appDataPathProvider);
    if (!await file.exists()) {
      return null;
    }

    try {
      final String rawJson = await file.readAsString();
      if (rawJson.trim().isEmpty) {
        return null;
      }

      final Object? decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return null;
      }

      return UserProfile.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required UserProfile profile,
    required Future<String?> Function() appDataPathProvider,
  }) async {
    final File file = await _resolveFile(appDataPathProvider);
    await file.parent.create(recursive: true);

    final String jsonString =
        const JsonEncoder.withIndent('  ').convert(profile.toJson());

    final File temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonString, flush: true);
    await temp.rename(file.path);
  }

  Future<void> clear({
    required Future<String?> Function() appDataPathProvider,
  }) async {
    final File file = await _resolveFile(appDataPathProvider);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _resolveFile(
    Future<String?> Function() appDataPathProvider,
  ) async {
    final String? appData = await appDataPathProvider();
    if (appData == null || appData.trim().isEmpty) {
      return File('${Directory.systemTemp.path}/$_fileName');
    }
    return File('$appData/$_fileName');
  }
}
