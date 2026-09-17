import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/services/model_manager.dart';
import 'package:sih_voice_bridge/app/services/native_bridge_service.dart';
import 'package:sih_voice_bridge/app/ui/screens/language_setup_screen.dart';

class _SlowModels extends ModelManager {
  _SlowModels(this.ready, NativeBridgeService bridge)
      : super(
            appDataDirectoryPath: () async => null,
            nativeBridgeService: bridge);
  final Completer<void> ready;
  @override
  Future<void> initialize() => ready.future;
}

void main() {
  testWidgets('first frame shows choices while model initialization is pending',
      (tester) async {
    final ready = Completer<void>();
    final bridge = NativeBridgeService();
    final models = _SlowModels(ready, bridge);
    await tester.pumpWidget(MaterialApp(
        home: LanguageSetupScreen(
            modelManager: models, onComplete: (_) async {})));
    expect(find.text('Choose your languages'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final english = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'English'));
    expect(english.value, isTrue);
    expect(english.onChanged, isNotNull);
    await tester.tap(find.text('Hindi'));
    await tester.pump();
    await tester.tap(find.text('Gujarati'));
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Hindi'))
            .value,
        isTrue);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Gujarati'))
            .value,
        isFalse);
    ready.complete();
    await tester.pump();
    // A late restore must not replace a choice the user already made.
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Hindi'))
            .value,
        isTrue);
    await tester.pumpWidget(const SizedBox());
    models.dispose();
    await bridge.dispose();
  });
}
