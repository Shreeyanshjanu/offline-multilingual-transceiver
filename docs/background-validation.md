# Background connection validation

Date: 17 September 2026. Tested workspace: `feature/persistent-connection-20260917` with the user's pre-existing uncommitted changes preserved.

## Automated checks

| Check | Result |
| --- | --- |
| Flutter analyzer | No issues found. |
| Flutter regression suite | 75 passed: 67 existing and 8 background-connection tests. |
| Kotlin unit suite | 13 passed: 9 existing audio pipeline and 4 TCP/backoff tests. |
| Debug app APK | Built successfully with compileSdk/targetSdk 36, minSdk 24. |
| Instrumentation APK | Built successfully. |
| Native protocol/journal instrumentation, Android 16 | 3 passed. |
| Native protocol/journal instrumentation, Android 14 | 3 passed. |
| Service lifecycle instrumentation, Android 14 | 1 passed, 70.2 seconds. |
| Normal repository `git diff --check` | Passed. |
| Conflict-marker scan of source/test files | No merge conflict markers found. |
| Protected source/configuration comparison | Unchanged against the pre-feature snapshot; inventory lists exact files. |
| APK ONNX model entries | Zero; verified by examining ZIP entries. |

The lifecycle instrumentation is opt-in and emulator-only. It starts a visible activity, starts the real foreground service, removes the application's own tasks, verifies persistence/deduplication and native sending, reopens without another service/peer, and invokes the notification's actual Disconnect PendingIntent. It also verifies that the saved request is cleared and the closed peer is not reconnected. The first run exposed a desktop-emulator test assumption about keyboard focus; replacing that assumption with Android's activity idle synchronization allowed the test to exercise the service and pass. No production behavior was changed to accommodate the test.

## Physical Android 16 phone

Device: Moto g85 5G / API 36. Controlled Python peers ran on the development computer over adb forwarding/reverse forwarding. No messages were sent to another person's device.

| Scenario | Evidence/result |
| --- | --- |
| Native leader with two peers | Both connections accepted; service foreground type `0x00000200` (`remoteMessaging`). |
| Foreground reception | Record `bg-verification-1789645612128295700`; relayed to the other peer; TTS audio-start and completion callbacks. |
| Home | Same two sockets remained; message `bg-verification-1789645614751798900` received, relayed, persisted, and completed playback callbacks. |
| Duplicate packet | Repeating the same ID did not create another relay, stored entry, or TTS start. |
| Swipe iTantra from Recents | `Task removed; requested connection remains active` logged. Same service and sockets remained. |
| Delivery after Recents removal | `bg-verification-1789645787941660700` received and relayed; persisted with TTS audio-start and playback-finished status. |
| Reopen after Recents removal | UI displayed CONNECTED / BACKGROUND ACTIVE and the stored test message; two original peers remained; no new playback for repeated ID. |
| Notification Disconnect | Actual notification action tapped; both peers closed; service removed; saved `connection_requested=false`. |
| UI Disconnect during retries | Service stopped and persisted cancellation; no later retry/start observed. |
| Notification allowed | Ongoing notification displayed, with Disconnect action and no message contents. |
| Notification denied | Verified `POST_NOTIFICATIONS: granted=false`, then started a fresh service from Connect. `bg-verification-1789646165992182900` received with native audio-start callback. Permission restored to the original granted state afterward. |
| Android Active Apps Stop | Official `cmd activity stop-app` stopped process/service. Service remained absent; reopening restored disconnected UI and did not reconnect. |
| Native client | Joined controlled listener through adb reverse; received `bg-verification-1789646370964597100`. |
| Client peer loss | EOF caused RECONNECTING, a 1,000 ms retry, then CONNECTED. Subsequent message `bg-verification-1789646401600700200` received. |
| Capped backoff | Failed endpoint test showed 1, 2, 4, 8, 15, then 30-second delays; exact sequence/reset/cancellation also covered by unit tests. |
| Screen off / AOD | Android reported `mWakefulness=Dozing` before and after delivery of `bg-verification-1789646518359068900`; native TTS reported audio starting. |
| Simulated process loss | Debug app process killed with `run-as ... kill -9`; OS recreated service in a new process and reconnected. It respected saved intent; no app-level restart alarm/job was involved. |
| Deduplication after recreation | Repeating `bg-verification-1789646518359068900` produced no new reception/playback record. New ID `bg-verification-1789646561743945800` received with TTS audio-start. |
| Flutter outgoing message | Typed a labeled verification message in Messages; controlled peer received ID `1789646640765945`. |
| Background switch OFF/ON | OFF saved false and stopped ownership. ON while disconnected did not start service until Connect. Turning OFF with native leader active stopped the service. |

Native audio callbacks establish that the Android TTS engine started audio and, for completed samples, reported completion. The phone's media volume was initially zero; no acoustic audibility claim is made and its volume was not raised for testing.

## Remaining physical/version validation

- No API 31, 33, or 35 device/image was installed. Android 12, 13, and 15 runtime behavior still needs testing on those versions.
- No physical Wi-Fi interruption/recovery test was completed. TCP EOF/reconnect, capped failures, task lifecycle, and persistence were tested; adb loopback does not prove a real Wi-Fi link survives or recovers.
- Screen-off/AOD evidence does not establish behavior through extended deep Doze or vendor-specific battery restrictions.
- Process loss was simulated; actual low-memory termination timing and repeated OEM kills were not reproduced.
- Active Apps Stop was verified. The distinct Force Stop behavior is documented but was not separately exercised as a lifecycle acceptance test.
- Full acoustic STT/TTS, all installed languages/voices, emergency audio, and prolonged continuous capture were not re-audited on hardware. Their existing regression tests passed and protected model/STT sources were unchanged.
- No reboot implementation or test was performed. Google Play declarations/submission remain a release task.

## Cleanup and artifacts

The phone's notification permission was restored to granted. The test connection was stopped and background mode returned to OFF, with `connection_requested=false`. Leader configuration was restored to host mode with `192.168.4.1:7070`. User profile, installed models, existing history, and application data were preserved. Clearly labeled verification messages remain in history.

Test peers, the emulator launched for this work, and only the test adb forwarding/reverse rules were cleaned up. No Play submission or model release changes were performed during validation.

Files:

- `background-service-device.log`: content-free native service lifecycle logs from the phone.
- `background-message-evidence.json`: verification IDs and stored playback/read metadata.
- `background-connection-inventory.json`: exact source inventory, protected-file comparison, and APK SHA-256.
- `background-connection-source.md`: full source of every Kotlin/Dart file changed for the feature, manifest, tests, helper, and guide.
- `background-connection-source.zip`: the same implementation at project-relative paths with documentation and this validation report.

Raw build/test logs remain under `.git/codex-background-20260917/`; the pre-task source backup is in its `before/` folder. The documentation in `docs/background-connection.md` provides exact build/run/adb commands and official Android/Google policy references.
