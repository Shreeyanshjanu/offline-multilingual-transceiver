import 'package:flutter/material.dart';

import '../../models/language_option.dart';
import '../../services/model_manager.dart';

class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen(
      {super.key, required this.modelManager, required this.onComplete});
  final ModelManager modelManager;
  final Future<void> Function(List<LanguageOption> languages) onComplete;
  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen>
    with WidgetsBindingObserver {
  final Set<String> _selected = {'en'};
  bool _busy = false;
  bool _edited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The first frame contains the choices even if storage/native calls are slow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restore();
    });
  }

  Future<void> _restore() async {
    try {
      await widget.modelManager.initialize();
      if (!mounted || _busy || _edited) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(widget.modelManager.selectedLanguages);
        _error = null;
      });
      if (widget.modelManager.setupComplete) {
        await _finish();
      } else if (widget.modelManager.hasPendingSetup) {
        await _continue();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await widget.modelManager.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _toggle(String code) {
    setState(() {
      _edited = true;
      _error = null;
      if (_selected.contains(code)) {
        if (_selected.length > 1) _selected.remove(code);
      } else if (_selected.length < ModelManager.maxSelectedLanguages) {
        _selected.add(code);
      } else {
        _error = 'You can select at most 2 languages.';
      }
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.modelManager.downloadSelection(_selected.toList());
      if (!mounted) return;
      await _complete();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _complete();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() => widget.onComplete(
        _selected
            .map((code) => kLanguageOptions
                .firstWhere((language) => language.code == code))
            .toList(),
      );

  Future<void> _remove(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.modelManager.delete(code);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.modelManager,
      builder: (context, _) {
        final String? active = widget.modelManager.activeLanguage;
        return Scaffold(
          appBar: AppBar(title: const Text('Language Setup')),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (active != null) ...[
                    const SizedBox(height: 12),
                    Text(
                        '${kLanguageOptions.firstWhere((language) => language.code == active).label}: '
                        '${(widget.modelManager.progressFor(active) * 100).floor()}%'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: widget.modelManager.progressFor(active)),
                    Text(widget.modelManager.statusFor(active)),
                    const Text(
                        'The current download continues in the background. '
                        'Return here to finish setup.'),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _continue,
                    child: Text(_busy
                        ? 'Preparing your languages...'
                        : 'Download & Continue'),
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Choose your languages',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Select up to 2 languages. English is selected by default.'),
                const SizedBox(height: 8),
                Text('${_selected.length} / 2 languages selected'),
                const SizedBox(height: 12),
                for (final LanguageOption language in kLanguageOptions)
                  Card(
                    child: Column(children: [
                      CheckboxListTile(
                        value: _selected.contains(language.code),
                        onChanged: _busy ? null : (_) => _toggle(language.code),
                        title: Text(language.label),
                        subtitle: Text(
                            widget.modelManager.isDownloaded(language.code)
                                ? 'Downloaded'
                                : language.code.toUpperCase()),
                      ),
                      if (!_selected.contains(language.code) &&
                          widget.modelManager.isDownloaded(language.code))
                        TextButton(
                          onPressed:
                              _busy ? null : () => _remove(language.code),
                          child: Text('Remove ${language.label} download'),
                        ),
                    ]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
