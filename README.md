# iTantra – Offline Multilingual Voice Communication

iTantra is an Android application developed for the Smart India Hackathon (SIH). It is designed for low-latency voice communication over a local network using on-device speech recognition and speech synthesis.

## Current Working Flow

```
Voice input
   ↓
Offline STT
   ↓
Text message
   ↓
TCP over local Wi-Fi / hotspot
   ↓
Receiving device
   ↓
TTS
   ↓
Voice output
```

Typed messages can also be sent and converted to speech.

## Technology Stack

- **Flutter / Dart** — application UI
- **Kotlin** — native Android integration
- **Sherpa-ONNX** — offline speech processing
- **ONNX** — local speech models
- **TCP sockets** — local-network communication
- **Android** — target platform

## Project Structure

```
SIH/
├── android/
│   └── app/src/main/kotlin/com/sih/voicebridge/
│       ├── bridge/          # Flutter channel dispatch
│       ├── connection/      # Optional native background TCP service
│       ├── download/        # Persistent Android model downloads
│       ├── location/        # GPS integration
│       ├── network/         # Wi-Fi gateway discovery
│       └── pipeline/        # Audio capture, STT, TTS, and orchestration
├── assets/
│   └── models/              # STT/TTS manifests and release source assets
├── lib/
│   ├── main.dart
│   └── app/
│       ├── app.dart         # Setup and app initialization
│       ├── models/
│       ├── services/        # Downloads, storage, TCP, and native bridge
│       │   └── native_bridge/
│       ├── state/           # Controller and private event/message/benchmark helpers
│       ├── theme/
│       └── ui/
│           ├── app_shell.dart
│           ├── screens/    # Language setup, Talk, and Messages
│           └── widgets/
│               ├── talk/
│               ├── messages/
│               ├── profile/
│               └── settings/
├── test/
├── docs/
├── pubspec.yaml
└── README.md
```

The screens compose focused widgets. `AppController` owns shared application
state; its private library parts handle native events, message dispatch, and
benchmark recording. `NativeBridgeService` retains its public API while device
and download channel methods live under `services/native_bridge/`.

See the [UI map and user flows](docs/UI_MAP_AND_USER_FLOWS.md) for the active
screens and their responsibilities.

## Requirements

Install the following before running the project:

- Git
- Flutter SDK
- Android Studio
- Android SDK
- Android SDK Platform Tools
- Android emulator or a physical Android phone

> A physical Android phone is recommended for testing the microphone, speaker, STT, TTS, and local-network communication.

## Install Flutter

Install Flutter from the official Flutter documentation:

https://docs.flutter.dev/get-started/install

Verify the installation:

```bash
flutter --version
```

Then run:

```bash
flutter doctor
```

Fix any Android/Flutter setup issues reported by `flutter doctor`.

Check connected devices:

```bash
flutter devices
```

## Clone the Repository

```bash
git clone https://github.com/Shreeyanshjanu/offline-multilingual-transceiver.git
cd offline-multilingual-transceiver
```

Install Flutter dependencies:

```bash
flutter pub get
```

## Run the Application

Connect an Android phone with USB debugging enabled, or start an emulator.

Check devices:

```bash
flutter devices
```

Run the application:

```bash
flutter run
```

To select a specific device:

```bash
flutter run -d DEVICE_ID
```

Example:

```bash
flutter run -d ZA222MVV6T
```

## Testing Communication

The application uses a local TCP network. The current application port is:

```
7070
```

A typical setup is:

```
Phone B ──┐
Phone C ──┼──> Phone A (Server / Relay)
Phone D ──┘
```

One device runs as the server/relay and other devices connect to it.

Messages are transmitted as text rather than raw voice audio. The receiving device performs TTS locally.

### Background Connection

In Talk, open Radio diagnostics and settings and enable **Keep Connection Active
in Background**, then start or join a mesh. The native Android foreground service
keeps the connection active when the app is minimized or removed from Recents.
Incoming messages are stored locally and use native TTS. Disconnect in the app
or notification stops the service and cancels reconnect attempts.

See the [background connection guide](docs/background-connection.md) for setup,
lifecycle behavior, build commands, and Android limitations, and the
[validation results](docs/background-validation.md) for tested scenarios.

## Working on the UI

Most UI development happens inside:

```
lib/
```

Start by exploring:

```
lib/app/ui/screens/
lib/app/ui/widgets/
lib/app/theme/
```

UI contributors can work on:

- Screens
- Widgets
- Layouts
- Colors
- Typography
- Spacing
- Icons
- Animations
- Themes
- User experience

### Important

If you are working only on the UI, avoid changing the underlying:

- `android/`
- `assets/models/`
- native MethodChannels
- STT pipeline
- TTS pipeline
- TCP/networking

...unless your task specifically requires it.

The native speech pipeline is sensitive, so UI changes should preferably remain within the Flutter layer.

## Flutter Hot Reload

Run:

```bash
flutter run
```

After changing Dart UI code, save the file and Flutter will normally hot-reload the application.

If needed, press `r` in the Flutter terminal for hot reload. For a full restart, press `R`.

## Build an APK

Debug APK:

```bash
flutter build apk --debug
```

Normally generated at:

```
build/app/outputs/flutter-apk/app-debug.apk
```

Release APK:

```bash
flutter build apk --release
```

Normally generated at:

```
build/app/outputs/flutter-apk/app-release.apk
```

## Native Android Code

Native code is located under:

```
android/app/src/main/kotlin/
```

Speech recognition code is located under:

```
android/app/src/main/kotlin/com/sih/voicebridge/pipeline/
```

`SttEngine.kt` manages STT sessions and language changes. `SttAssetResolver.kt`
locates installed models; `SherpaOnnxBackendFactory.kt`,
`SherpaOnnxReflectiveBackend.kt`, and `SttReflection.kt` handle Sherpa integration.
Shared STT interfaces live in `SttContracts.kt`.

`TtsEngine.kt` chooses the speech backend. Model resolution, Android system TTS,
and Piper/Sherpa TTS live in `TtsModelResolver.kt`, `AndroidSystemTtsBackend.kt`,
and `PiperSherpaTtsBackend.kt`, with shared types in `TtsContracts.kt`.

> Do not modify native speech-processing code for a UI-only task.

## Offline Models

Speech model manifests and release source assets are stored under:

```
assets/models/
```

The application is designed to process speech locally without depending on cloud speech APIs.

On first launch, select up to two of the ten available languages. Internet access is required to download their STT models and tokenizers. Android DownloadManager owns the current transfer while the app is backgrounded. Reopening setup restores the queue and verifies both files before enabling recognition.

The APK includes model manifests only. Downloaded models keep the existing internal `files/stt_models/` paths. Model binaries retained in this repository are release assets. Android TTS availability depends on the voices installed on the device.

See [setup and transport validation](docs/setup-validation.md) for automated checks and Home/resume testing.

> Model files can be large. Do not add or replace large model files without checking their size and licensing first.

## Git Workflow

Do not work directly on `main` for new features.

Create a feature branch:

```bash
git checkout -b ui-improvement
```

Make and test your changes.

Check:

```bash
git status
git diff
```

Commit:

```bash
git add .
git commit -m "Improve application UI"
```

Push:

```bash
git push -u origin ui-improvement
```

Then create a Pull Request on GitHub.

Example branches:

```
main
├── ui-improvement
├── improve-stt-accuracy
└── emergency-ui
```

## Before Creating a Pull Request

Run:

```bash
flutter analyze
```

and:

```bash
flutter test
```

then:

```bash
flutter build apk --debug
```

Also verify:

- [ ] UI works on Android
- [ ] Voice communication still works
- [ ] Typed messages still work
- [ ] TCP communication still works
- [ ] No API keys or passwords were committed
- [ ] No generated build directories were committed
- [ ] Changes are on a feature branch

## Troubleshooting

**Flutter is not recognized**

Make sure Flutter's bin directory is in PATH, then restart the terminal:

```bash
flutter --version
```

**Android device is not detected**

Run:

```bash
flutter devices
```

For a physical phone, enable Developer Options and USB debugging and accept the computer authorization prompt.

You can also check:

```bash
adb devices
```

**Multiple Android devices are connected**

List devices:

```bash
flutter devices
```

Then select one:

```bash
flutter run -d DEVICE_ID
```

**Build problems after dependency changes**

Try:

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

## Development Roadmap

Current development priorities include:

- Improve STT accuracy
- Improve microphone/audio processing
- Add more Indian languages
- Improve offline TTS
- Improve Flutter UI/UX
- Improve emergency communication
- Test on low- and mid-range Android devices
- Measure latency, CPU, RAM, and APK size

## Contributing

For UI contributors:

1. Clone the repository
2. Install Flutter and Android tooling
3. Create a feature branch
4. Make UI changes in `lib/`
5. Test on Android
6. Run `flutter analyze`
7. Build a debug APK
8. Commit your changes
9. Push your branch
10. Create a Pull Request

## License

Add the project's final license information here before public release.

Third-party libraries and speech models may have separate licenses. Check their licenses before redistribution.
