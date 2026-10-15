# Speech-following design and validation

Follow Voice is implemented as an optional macOS 26+ feature tracked by Bean `cueglass-2mil`. CueGlass keeps its macOS 14 deployment target. Deterministic tests and a macOS 14-target build do not establish live recognition quality; human-speech acceptance remains pending as recorded below.

## Native APIs and permission boundary

Apple's [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) and [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) support on-device streaming transcription from macOS 26. `SpeechVoiceSource` is marked `@available(macOS 26.0, *)`; the operator creates it only inside an availability check when `SpeechTranscriber.isAvailable` is true. The UI is absent on macOS 14–25 and when the device reports transcription unavailable.

The system adapter checks `SpeechTranscriber.supportedLocales`, installed locales and `AssetInventory.status` without requesting microphone access or downloading models. It offers supported locales and explains that English is the validated language. A separate Install Speech Model button is the user's consent to call `AssetInventory.assetInstallationRequest(...).downloadAndInstall()`. The adapter displays the request's actual `Progress`, supports Cancel, and rechecks readiness after installation. It does not start microphone capture or analysis until model readiness is confirmed and the operator later presses Start.

Only explicit Start checks `AVAudioApplication.recordPermission` and requests microphone access when permission is undetermined. A denial prevents capture and offers a link to Privacy & Security → Microphone. `NSMicrophoneUsageDescription` and `com.apple.security.device.audio-input=true` are included in the local plist/entitlement and tracked iCloud example/entitlement. Start fails closed if the built app has no nonempty usage string. The actual owner-copied iCloud plist remains gitignored and must be refreshed from the example; see [iCloud owner setup](../ICLOUD_SETUP.md).

Apple's [Speech permission guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) applies to `SFSpeechRecognizer` and server recognition. Follow Voice uses `SpeechAnalyzer`/`SpeechTranscriber`; it does not call `SFSpeechRecognizer.requestAuthorization` and adds no `NSSpeechRecognitionUsageDescription`.

## Alignment and shared playback

`VoiceFollowCore` tokenizes the immutable prepared `ScriptSnapshot` into normalized words and UTF-16 source ranges. The active TextKit 2 viewport builds an immutable line/fragment table after measurement. It maps token offsets to layout Y coordinates and invalidates the table whenever the viewport is configured for a new snapshot or layout. Transcript alignment and layout mapping stay outside display callbacks.

`PlaybackSession` remains the only timeline for preview, fullscreen and floating output. `PlaybackTimeline`'s optional voice ceiling lets its existing time-based motion glide toward a confirmed script position and stop at that point without per-frame recognition work. The configured maximum LPM caps glide speed. Volatile transcript updates do not seek; confirmed discontinuities use a jump. A bounded transcript accumulator and newest-buffer/result streams keep transient state finite. Stale decisions carry an epoch and are ignored after stop or manual input.

The policy holds on silence, low confidence, mismatches and loss of lock, and attempts local or whole-script reacquisition after skips and rereads. Manual pace/navigation/scrub/pause and layout changes close the mic, suspend voice priority, and pause the shared timeline at the operator's chosen position. Only Play/Space or the explicit Resume control may re-arm following. Switching to Timed Scrolling ends the voice session and starts the selected timed take; Follow Voice disables the timed deadline. Stop Follow Voice, Stop Take, window close, sleep, audio-device/configuration loss and errors stop the analyzer/engine, remove the tap, finish bounded streams and clear transcript memory. Stop preserves the selected locale's model-readiness state and the denied-microphone recovery state.

Speech/audio content is not written to logs, documents, files or preferences. Only the selected locale is an app preference. Capture buffers exist transiently in a bounded stream for analysis; no recording is produced or retained.

## Research evidence

The standalone experiment at `73ecfb6e40bcb0869e51eb9b38ad09513048eeda` showed feasibility using generated speech, not a live microphone or human speaker. Its macOS 27.0.1 M5 Max run reported a median position lag of two words, recovery from its scripted skip and reread, and a hold during silence. That result is algorithm evidence only; it does not establish human voice, room, microphone, latency, sustained-take or cross-Mac quality. The experiment's pure alignment/policy and deterministic scenarios were ported into `CueFlowCore`; its separate production timeline was not.

## Verification status

On 2026-10-14 the available host reported macOS 27.0.1 and Xcode 27.0. The unsigned DebugLocal app compiled for `arm64-apple-macos14.0` against the macOS 27 SDK. `swift test --package-path Packages/CueFlowCore --scratch-path .build/core` passed 41 tests; after the source-review corrections, `scripts/test-app.sh` passed 70 native tests across three suites, including clock-advanced manual-pause, surface-transition, permission, model-readiness and TextKit mapping checks. Strict Swift formatting passed. The macOS 14 deployment target compiles with the current SDK; no macOS 14 runtime test was performed. The conditional iCloud build was not run because `Configuration/Owner.xcconfig` and `Configuration/Info-iCloud.plist` were absent.

The full independent review of `bb0472138261d3050cfe145efe435c187bda9dd3` found two blocking manual-priority defects. The corrections are in the current working tree and pass the local deterministic suite; a fresh independent review and CI run are still required before live acceptance. No live human-speech result is claimed. Fresh microphone permission prompt/denial/settings recovery; missing-model consent, progress, cancellation and installation; silence; ad-lib; skip; reread; manual and surface override/resume; Timed Scrolling handoff; and a sustained human take remain pending on macOS 26+.
