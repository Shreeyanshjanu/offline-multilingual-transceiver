import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/gps_location.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/state/app_controller.dart';
import 'package:sih_voice_bridge/app/ui/screens/messages_screen.dart';
import 'package:sih_voice_bridge/app/ui/widgets/radio_settings_sheet.dart';
import 'package:sih_voice_bridge/app/ui/widgets/tactical_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.sih.voicebridge/native_events'),
      (MethodCall call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.sih.voicebridge/native'),
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.sih.voicebridge/native_events'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.sih.voicebridge/native'),
      null,
    );
  });

  group('Responsive Layout Tests across Screen Sizes', () {
    const List<Size> testViewports = <Size>[
      Size(320, 640), // Ultra-compact / Galaxy Z Fold outer / Split screen
      Size(360, 800), // Standard budget/compact Android device
      Size(392, 872), // Standard Redmi Note 11 / Pixel 7 device
      Size(412, 915), // Large flagship device
    ];

    for (final Size viewport in testViewports) {
      testWidgets(
        'TacticalHeader renders without overflow on ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (WidgetTester tester) async {
          tester.view.physicalSize =
              Size(viewport.width * 2, viewport.height * 2);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final AppController controller = AppController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TacticalHeader(
                  controller: controller,
                  activeTabTitle: 'TALK',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          // Verify Tune button is present and found
          expect(find.byIcon(Icons.tune), findsOneWidget);
        },
      );

      testWidgets(
        'MessagesScreen renders SOS with GPS without overflow on ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (WidgetTester tester) async {
          tester.view.physicalSize =
              Size(viewport.width * 2, viewport.height * 2);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final AppController controller = AppController();
          addTearDown(controller.dispose);

          // Add emergency message with full GPS telemetry
          final GpsLocation testLocation = GpsLocation(
            latitude: 28.613929,
            longitude: 77.209021,
            altitude: 216.5,
            accuracy: 5.2,
            provider: 'gps',
            timestamp: DateTime.now(),
          );

          controller.addTestMessage(
            SpeechMessage(
              id: 'test_sos_1',
              type: MessageType.emergency,
              languageCode: 'en',
              message:
                  'Medical assistance required for Bravo-6 (Combat Medic) [GPS: 28.6139° N, 77.2090° E]',
              timestamp: DateTime.now(),
              origin: MessageOrigin.local,
              senderCallsign: 'Bravo-6',
              senderRole: 'Combat Medic',
              location: testLocation,
            ),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MessagesScreen(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Assert zero RenderFlex overflow exceptions occurred
          expect(tester.takeException(), isNull);
          expect(find.textContaining('LOCATION: 28.6139° N, 77.2090° E'),
              findsOneWidget);
          expect(find.textContaining('ACCURACY: ±5m'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'TacticalHeader and MessagesScreen resist severe 1.35x accessibility font scale on 360x800',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360 * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final AppController controller = AppController();
        addTearDown(controller.dispose);

        controller.addTestMessage(
          SpeechMessage(
            id: 'test_sos_scale',
            type: MessageType.emergency,
            languageCode: 'en',
            message: 'Urgent medical beacon triggered',
            timestamp: DateTime.now(),
            origin: MessageOrigin.local,
            senderCallsign: 'Alpha-Leader',
            senderRole: 'Team Commander',
            location: GpsLocation(
              latitude: 19.076090,
              longitude: 72.877426,
              altitude: 14.0,
              accuracy: 3.8,
              provider: 'gps',
              timestamp: DateTime.now(),
            ),
          ),
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.35),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: <Widget>[
                    MessagesScreen(controller: controller),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: TacticalHeader(
                        controller: controller,
                        activeTabTitle: 'MESSAGES',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('LOCATION: 19.0761° N, 72.8774° E'),
            findsOneWidget);
      },
    );

    testWidgets(
      'RadioSettingsSheet renders without overflow on 320x640',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320 * 2, 640 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final AppController controller = AppController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RadioSettingsSheet(controller: controller),
            ),
          ),
        );
        // RadioSettingsSheet includes a PulsingDot with infinite repeating animation; use bounded pump
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.text('OPERATOR & TELEMETRY'), findsOneWidget);
        expect(find.text('EDIT'), findsOneWidget);
      },
    );
  });
}
