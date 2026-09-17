import 'package:flutter/material.dart';

import 'models/language_option.dart';
import 'services/model_manager.dart';
import 'services/native_bridge_service.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';
import 'ui/screens/language_setup_screen.dart';

class SihVoiceBridgeApp extends StatefulWidget {
  const SihVoiceBridgeApp({super.key});
  @override
  State<SihVoiceBridgeApp> createState() => _SihVoiceBridgeAppState();
}

class _SihVoiceBridgeAppState extends State<SihVoiceBridgeApp> {
  final NativeBridgeService _bridge = NativeBridgeService();
  late final ModelManager _models;
  AppController? _controller;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _models = ModelManager(
      appDataDirectoryPath: _bridge.getAppDataDirectoryPath,
      nativeBridgeService: _bridge,
    );
  }

  Future<void> _finishSetup(List<LanguageOption> languages) async {
    if (_starting || _controller != null) return;
    if (languages.isEmpty ||
        !languages.every((language) => _models.isDownloaded(language.code))) {
      throw StateError(
          'Selected model and tokenizer files must be verified first.');
    }
    _starting = true;
    final AppController controller = AppController(
      nativeBridgeService: _bridge,
      ownsNativeBridge: false,
      availableLanguageCodes: languages.map((language) => language.code),
    );
    try {
      await controller.initialize(initialLanguageCode: languages.first.code);
      if (!mounted) {
        controller.dispose();
        return;
      }
      await _models.markSetupComplete();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      controller.dispose();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  @override
  void dispose() {
    _models.dispose();
    _controller?.dispose();
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'iTantra Voice Bridge',
        theme: AppTheme.dark(),
        home: _controller == null
            ? LanguageSetupScreen(
                modelManager: _models, onComplete: _finishSetup)
            : AppShell(controller: _controller!),
      );
}
