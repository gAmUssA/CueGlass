# Title

Follow Voice microphone continuity, truthful input routing, and catch-up glide

# Status

accepted

# Date

2026-10-17

# Context

ADR 0007 accepted that the microphone, transcript accumulator and bounded streams are cleared on an audio-device or configuration failure. With an external microphone attached, the owner saw Follow Voice end the session whenever macOS posted `AVAudioEngineConfigurationChange` (a microphone plugged, unplugged or switched, or a sample-rate change) and saw the guide trail confirmed speech by seconds because the glide never exceeded the cadence cap.

Independent review of the first continuity implementation found three gaps. Choosing System Default after an explicit device did nothing at the input unit, so capture stayed on the previously selected device while the picker showed the default. A refused device selection was discarded, so the picker could show a device that was not capturing. Startup published the engine before the analyzer finished preparing, so a device change during that window could install a second tap on the same bus; Apple documents one tap per bus.

Options considered: keep ending the session on every configuration change (loses the take position the owner is reading from); recreate the whole analyzer on each change (seconds of silence and a transcript restart); rebuild only the audio input under one owner that reads the route back from the unit.

# Decision

Supersedes the configuration-change clause of ADR 0007. Everything else in ADR 0007 stands: one shared timeline, the voice ceiling, manual priority, and clearing capture on stop, suspension, close, sleep and error.

- A configuration change no longer ends the session. The capture source rebuilds only the audio input — same engine, same analyzer, same transcript stream, same take — on the new input format. A device that provides no usable format after a bounded retry still ends capture through the existing failure path.
- One owner, `VoiceCaptureRouter`, holds the input route and the single tap for a capture. Startup opens the route, waits for a usable format, and installs the tap only after the analyzer has prepared. A device or device-list change while the analyzer is preparing is recorded and applied when the tap goes in; while live it is applied immediately by removing the tap, re-routing, and installing one new tap. No second installer exists.
- The route is explicit and read back. System Default selects the current default input device on the unit rather than leaving the previous device in place; a remembered device that is absent selects the default explicitly; a refused selection keeps the previous device. After every selection the router reports what the unit actually uses, including the fallback or failure, and the coordinator and inspector show that route and its reason. The remembered choice is kept by device UID so the device is used again when it returns.
- Catch-up glide. When confirmed speech places the reading line more than half a line ahead of the display, the glide velocity rises so the guide reaches that line within 0.7 s, never below the cadence or the operator's baseline and never above the configured maximum. Volatile wording still cannot raise the speed, and the voice ceiling still stops the page at the spoken line.

# Consequences

Hot-plugging or switching a microphone keeps the take and its position; the operator hears at most a short gap. The picker's effective device is the unit's answer, not the device list's, so a failed switch is visible instead of silent. The router is Foundation and AVFAudio only, so its routing, fallback, refusal, tap-ownership and preparation-window behaviour is covered by deterministic tests on macOS 14 hosts without microphones; `SpeechVoiceSource` stays macOS 26+. Later work must keep one tap owner per capture, must not select a device without reading the route back, and must keep the catch-up bounded by the configured maximum. Live multi-microphone switching, hot-plug and human-perceived catch-up remain manual acceptance rows.
