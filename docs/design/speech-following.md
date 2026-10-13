# Speech-following feasibility

Native speech-following looks feasible enough to prototype. It is not implemented in CueGlass, and recognition latency or tracking accuracy has not been measured. The owner permits a macOS 26 baseline if needed; the current app remains compatible with macOS 14.

## Native APIs

Apple's [SpeechAnalyzer and SpeechTranscriber](https://developer.apple.com/videos/play/wwdc2025/277/) support on-device, long-form speech transcription with streaming results and audio timing. They are available from macOS 26. Volatile results arrive earlier and may be revised; final results arrive later. Models require an initial download, so offline behavior must be tested after installation and after asset changes.

[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) exposes runtime device and language checks. A read-only probe on the development Mac (macOS 27) returned `isAvailable=true` and installed English locales. It opened no microphone and downloaded no models. This proves capability on that machine, not transcription quality or support across all Macs. Russian was absent from that machine's supported-locale result.

Apple Intelligence's [Foundation Models framework](https://developer.apple.com/foundation-models-framework/) is a separate language-model API. A language model is not necessary for the real-time scroll-control path.

## Proposed follow behavior

Match recognized tokens to the known, immutable script. Words per minute alone cannot identify the presenter's position and would drift after skips, repetitions or ad-libs.

Recognition and incremental alignment should run outside display callbacks. Keep token-to-source offsets separate from layout coordinates, which change after typography or window resizing. Use confident matches to adjust the existing shared timeline smoothly; finalized transcription can still have an incorrect script alignment, so later recovery must remain possible.

Pause or hold on silence and lost confidence. Scrubbing, stepping, speed changes and Pause take priority and suspend following until it is explicitly resumed. Keep Timed Scrolling and speech-following as separate modes.

## Baseline and prototype

A macOS 26-only Follow feature can coexist with a macOS 14 app through availability checks. Raising the whole app's baseline is optional and should follow prototype evidence. The legacy recognition API's documented short-task limitations make it a poor default for uninterrupted long takes.

Start with prerecorded audio and injected-clock replay, then measure result latency, script-position error, recovery after skips/repeats, false motion during silence/ad-libs, offline behavior and a sustained take. Only then assess a live microphone integration. That implementation would need verified microphone entitlements, usage descriptions, authorization requirements, a visible listening state and an explicit audio-retention policy. Exact permission requirements must be checked for the chosen engine; they are not settled by this study.

No audio fixtures, recordings, microphone permissions or speech dependencies were added to the MVP by this research.
