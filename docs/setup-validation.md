# Language setup and transport validation

The first Flutter frame shows language choices with English selected. Storage
checks run after that frame and do not replace the choices with a loading screen.
The native voice pipeline is lazy: download/status/storage calls do not construct
the speech engines or bind Android TTS.

Before the first download, setup saves the selected languages in order and a
pending-setup flag. Android DownloadManager owns the current transfer and saves its
ID. Returning to a live app refreshes its status; after process recreation, setup
restores the queue, attaches to the existing ID, reconciles completed files, and
continues with the next language. A killed Flutter process cannot enqueue the next
file until the app returns. An Android force-stop can also suspend system work;
it is not equivalent to pressing Home.

A language is ready only when both model and tokenizer match the manifest's size
and SHA-256 digest. Hashing runs off the UI isolate. Completed files are copied to
a temporary file beside the destination, verified, and renamed into place.
Internal model paths remain:

- `files/stt_models/<language>/stt-<language>-model.int8.onnx`
- `files/stt_models/stt-en-tokens.txt`
- `files/stt_models/stt-indic-tokens.txt`

All Indic languages share the latter tokenizer. The bundled manifest records the
checksums of the matching files in `release-models/`. Update both release files
and manifest integrity metadata together when changing models. The APK includes
the manifests, not the ONNX models.

The server forwards validated newline-delimited JSON to other connected clients
without echoing to the sender. Receive buffers retain bytes until a full message
arrives, preserving UTF-8 across arbitrary TCP chunks. Malformed UTF-8 is rejected,
and a peer exceeding the 64 KiB frame limit is disconnected. Connection status
distinguishes a listening server from one with connected peers.

## Automated checks

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio1\jbr'
.\android\gradlew.bat -p android :app:testDebugUnitTest
flutter build apk --debug --no-pub
```

Tests cover first-frame choices with delayed storage, selection limits, unavailable
languages, missing/shared tokenizers, corrupt and partial files, saved download
IDs and queues, observer disposal, background reconciliation, retry, TCP relay,
split Hindi UTF-8, invalid packets, accessibility, and the existing speech pipeline.

### Results on 2026-09-17

- Flutter analysis: no issues; all 22 Flutter tests passed.
- Kotlin pipeline unit tests: all 9 passed; debug APK compilation succeeded.
- The rebuilt universal debug APK is 225,331,930 bytes (214.89 MiB). ZIP inspection
  confirmed both model manifests and zero ONNX files. Rebuilding the APK packaging
  state was necessary: the previous incremental archive retained unused bytes
  even after its model entries were removed.
- Installed the update on the connected moto g85 5G without clearing app data.
  Runtime widget inspection found `LanguageSetupScreen`, ten `CheckboxListTile`
  widgets, the action button, and no `CircularProgressIndicator`. App logs contained
  no early TTS initialization or fatal exception.
- The device remained locked, so visible interaction and real download/Home/resume
  checks were not completed. The cold debug launch still logged skipped frames;
  this check does not establish release startup performance.

## Device checks

1. On a fresh installation, verify language choices appear immediately and English
   is selected. Select a second language and start setup.
2. Press Home during a model download. Check the Android download notification,
   return, and verify progress resumes without a new transfer.
3. With the app backgrounded, allow Android to recreate its process (do not clear
   app data). Return and verify the selected queue and existing download ID resume.
4. Complete setup; switch between installed languages and verify PTT recognition.
   Uninstalled languages must not be offered in the main app's language controls.
5. Connect a host and two clients. Send Hindi text from one client. The host and
   the other client should receive it once, without an echo to the sender.
6. Test human microphone recognition and audible TTS separately. Automated fake
   download tests and loopback sockets do not establish acoustic accuracy or actual
   Android background scheduling behavior.
