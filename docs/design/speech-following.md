# Speech-following feasibility

Voice-following is not implemented in CueGlass. A standalone macOS 26 prototype measures paced synthetic audio on one development Mac; its results support feasibility but do not establish live microphone or human-speech quality. The app currently targets macOS 14.

## Native APIs

Apple's [SpeechAnalyzer and SpeechTranscriber](https://developer.apple.com/videos/play/wwdc2025/277/) support on-device, long-form speech transcription with streaming results and audio timing. They are available from macOS 26. Volatile results arrive earlier and may be revised; final results arrive later. Models require an initial download, so offline behavior must be tested after installation and after asset changes.

[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) exposes runtime device and language checks. A read-only probe on the development Mac (macOS 27) returned `isAvailable=true` and installed English locales. It opened no microphone and downloaded no models. This proves capability on that machine, not transcription quality or support across all Macs. Russian was absent from that machine's supported-locale result.

Apple Intelligence's [Foundation Models framework](https://developer.apple.com/foundation-models-framework/) is a separate language-model API. A language model is not necessary for the real-time scroll-control path.

## Proposed follow behavior

Match recognized tokens to the known, immutable script. Words per minute alone cannot identify the presenter's position and would drift after skips, repetitions or ad-libs.

Recognition and incremental alignment should run outside display callbacks. Keep token-to-source offsets separate from layout coordinates, which change after typography or window resizing. Use confident matches to adjust the existing shared timeline smoothly; finalized transcription can still have an incorrect script alignment, so later recovery must remain possible.

Pause or hold on silence and lost confidence. Scrubbing, stepping, speed changes and Pause take priority and suspend following until it is explicitly resumed. Keep Timed Scrolling and speech-following as separate modes.

## Integration recommendation

Keep CueGlass's deployment target at macOS 14. `SpeechAnalyzer`, `SpeechTranscriber`, and `AssetInventory` are macOS 26 APIs, so put the implementation behind a small `@available(macOS 26.0, *)` adapter and expose Follow Voice only when the OS, locale, and model are supported. This keeps the existing app available on macOS 14–25 while making voice-following an optional macOS 26 feature. The project must still compile with a macOS 26 SDK; its minimum deployment version can remain 14. Raising the whole app target would exclude users of macOS 14–25 without enabling a better Speech API.

Use [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer) with [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber) for long-form, on-device transcription. Apple's [WWDC25 live-transcription sample](https://developer.apple.com/videos/play/wwdc2025/277/) requests microphone access, streams audio buffers into the analyzer, and consumes volatile and finalized results asynchronously. The existing prototype already exercises that result path with paced prerecorded audio and keeps the transcript aligner independent of Speech APIs. The older [`SFSpeechRecognizer`](https://developer.apple.com/documentation/speech/sfspeechrecognizer) is a poor default for full presentations: Apple documents a one-minute task limit and possible network-based service throttling.

For a live session, request microphone permission only when the user starts Follow Voice. [`AVAudioApplication.requestRecordPermission`](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission%28completionhandler%3A%29) is available from macOS 14. Microphone capture requires an [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription) string plus Apple's [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input). Apply these to both the local and iCloud app configurations and verify the signed entitlements. Apple's live SpeechAnalyzer example requests audio permission; it does not show a legacy `SFSpeechRecognizer` authorization request. Confirm first-run behavior on a clean microphone privacy state before adding any legacy speech-authorization flow. Show an unmistakable listening state and a Stop control. Do not retain audio; feed capture buffers to the analyzer and release them after processing.

Before listening, check that the selected locale is supported and that its SpeechTranscriber assets are installed. If assets are missing, explain the download and ask before installing; show progress and let the user cancel. Apple's [`AssetInventory`](https://developer.apple.com/documentation/speech/assetinventory) manages these assets; the SpeechTranscriber model runs on-device and its assets are system-managed. Do not silently download models at app launch. The prototype currently refuses to run without installed assets and never downloads them.

Keep `VoiceFollowCore`'s word alignment and manual-priority policy separate from app UI and Speech capture. Add an app adapter that indexes the immutable `ScriptSnapshot` into normalized words with UTF-16 source ranges. Map accepted source offsets through the active TextKit 2 viewport to layout Y positions; recompute this mapping after text or layout changes. The current prototype returns token indexes, while `PlaybackSession` and `PrompterViewport` use layout points, so this mapping is required before the two can connect.

Drive the existing shared `PlaybackSession` so preview, fullscreen, and floating presentations continue to show one position. Do not call `seek(_:)` for every volatile recognition update: it resets the timeline anchor and would turn revised partials into visible jumps. Add a bounded voice-follow drive that consumes accepted script positions, glides smoothly toward them, holds on silence or low confidence, and reacquires after skips or repeats. Pause, Stop, scrubbing, stepping, and Timed Scrolling keep priority; resuming Follow Voice must be explicit. Recognition, alignment, and layout mapping stay off the display-link callback.

The synthetic experiment provides useful algorithm evidence only: on one M5 Max with macOS 27.0.1 it followed generated speech at a median of 2 words behind with `fastResults`, recovered from the test skip and reread, and held on silence. It does not measure human voices, room acoustics, live capture latency, longer takes, or other Macs. Keep deterministic tests for alignment, source-offset mapping, manual priority, and the position drive in CI. Validate the actual microphone path manually on a fresh macOS 26+ session, including permission denial, supported and unsupported locales, missing and installed assets, silence, ad-libs, skips, rereads, and a sustained human take.

This research update adds no microphone capture, permissions, or app speech dependency. The separately tracked implementation is Bean `cueglass-2mil`.
