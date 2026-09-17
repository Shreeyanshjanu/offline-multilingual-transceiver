import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sih_voice_bridge/app/app.dart';

void main() {
  testWidgets('App meets core Flutter accessibility guidelines',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final Directory directory =
        Directory.systemTemp.createTempSync('itantra-accessibility-');
    const channel = MethodChannel('com.sih.voicebridge/native');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'getAppDataDirectory' ? directory.path : null;
    });
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
    });
    final SemanticsHandle handle = tester.ensureSemantics();

    await tester.pumpWidget(const SihVoiceBridgeApp());
    await tester.pumpAndSettle();
    expect(find.text('Choose your languages'), findsOneWidget);
    expect(calls, isNot(contains('initializePipelines')));

    // 1. Android 48x48 tap target guideline
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    // 2. iOS 44x44 tap target guideline
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

    // 3. WCAG text contrast guideline
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // 4. Labeled tap targets for screen readers
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.scrollUntilVisible(find.text('Download & Continue'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
