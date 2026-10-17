# Title

Shared timeline voice-follow glide ceiling

# Status

accepted

# Date

2026-10-14

# Context

Follow Voice accepts normalized script tokens, while TextKit 2 uses UTF-16 offsets and viewport layout points. Recognition callbacks can arrive more often than meaningful alignment changes and may revise volatile words. Seeking the shared timeline on every update would create visible jumps and bypass its host-time motion. A second voice-only timeline would desynchronize preview, fullscreen and floating output.

# Decision

Keep the existing `PlaybackSession` and `PlaybackTimeline` as the only playback drive. After a confirmed token match, map its UTF-16 range through the active viewport's measured TextKit 2 line table and set an optional forward voice ceiling on the shared timeline. The timeline rebases at its current position and advances at the existing time-based velocity, capped to configured maximum LPM, until it reaches the ceiling. It never overshoots the confirmed target. A target behind the current point does not reverse the glide; only a confirmed discontinuity may seek and establish a new ceiling.

Silence, low confidence, mismatches and loss of lock hold the shared timeline at its current point. Transcript alignment remains outside display callbacks. Decisions include an epoch and are ignored after Stop or manual control. Every manual command closes microphone capture and suspends voice priority; Play/Space or explicit Resume may restart following. The manual seek clears the ceiling. Starting Follow Voice disables Timed Scrolling; selecting Timed Scrolling ends the voice session. The microphone, transcript accumulator and bounded streams are cleared on stop, suspension, close, sleep, audio-device/configuration failure and error. Neither audio nor transcript content is persisted.

# Consequences

Preview, fullscreen output and floating output continue sampling one timeline. Recognition revisions do not become per-frame seeks, and manual navigation remains authoritative until explicit resume. A layout remeasure invalidates the line table and requires a fresh measured table before following can start. The glide ceiling is transient session state and is never saved in the document. Deterministic tests cover UTF-16 lookup, line-table replacement, bounded movement, manual priority, epochs, silence and reacquisition. Live microphone, human-speech quality and macOS 26 permission/model flows remain separate manual acceptance gates.

## Catch-up glide and microphone continuity refinement (2026-10-17)

The owner reported sluggish following and dropped microphones with an external microphone attached. Two refinements, both inside the existing contracts:

- Catch-up glide. When confirmed speech places the reading line more than half a line ahead of the display, the glide velocity rises so the guide reaches that line within 0.7 s, never below the cadence or the operator's baseline and never above the configured maximum. Volatile wording still cannot raise the speed, and the voice ceiling still stops the page at the spoken line. `FollowCatchUp` in CueFlowCore carries the arithmetic.
- Microphone continuity. An audio configuration change (a microphone plugged, unplugged, or switched, or a sample-rate change) no longer ends the session. The capture source rebuilds only the input tap on the new format while the analyzer, the transcript stream, and the take continue; a device that cannot be reopened after a few retries still ends capture with the existing failure path. The operator can pick a specific microphone in the Follow Voice inspector; the choice is remembered by device UID and falls back to the system default while that device is absent. Changing it while following moves capture in place.
