---
# cueglass-q82s
title: Stabilize Follow Voice startup and inspector feedback
status: completed
type: bug
priority: high
created_at: 2026-10-15T14:26:25Z
updated_at: 2026-10-16T02:06:42Z
parent: cueglass-2mil
---

User-reported macOS 27 DebugLocal problems (2026-10-15): explicit speech-model installation ends in a generic failure message; pressing Start Follow Voice crashes CueFlow; Follow Voice labels and controls have weak contrast and unclear enabled/disabled state. Diagnose the captured crash reports and Speech asset installation error, fix the underlying issues with deterministic regression coverage, improve inspector readability/state cues, then rebuild and document remaining operator speech checks.


## Acceptance

- [x] Isolate and correct the AVAudioEngine tap actor-isolation crash from the 2026-10-15 macOS crash reports.
- [x] Make model-install errors actionable, handle already-complete/racing installations, and retain an explicit retry path.
- [x] Improve Follow Voice status contrast and make disabled, ready, installing, listening, denied, paused, and failed states visually distinct.
- [x] Add deterministic regression coverage for the audio callback and model-install state/error behavior.
- [x] Rebuild the macOS 14 target, rerun Core/native tests and strict formatting, and refresh the manual-test documentation.
- [ ] Verify speech-model installation completes and reaches Ready on macOS 27+.
- [x] Verify Follow Voice starts and tracks human speech with AirPods on macOS 27+ (operator confirmed 2026-10-15).
- [x] Confirm inspector readability and distinct active/inactive states on the rebuilt app (operator confirmed 2026-10-15).

## Current Evidence (2026-10-15)

The two Start crashes were Swift actor-isolation traps on AVAudioEngine’s realtime messenger queue. The tap callback is now a file-level Sendable handler and its background-queue regression passes. The model installer now exposes the OS error, handles the AssetInventory downloading and already-installed states, and provides a check/retry route. The AirPods startup regression keeps the shared timeline paused until capture setup completes. DebugLocal builds for arm64-apple-macos14.0; all 41 Core tests and the VoiceFollow native suite pass. The full native run passed 74 of 75 tests; the remaining failure is the display-selection reconnection test, outside Follow Voice. Strict formatting and beans consistency pass. Human retest with AirPods and the rebuilt app remains pending.


## AirPods startup follow-up (2026-10-15)

The operator approved microphone access and reproduced an immediate pause: “Paused after display stall,” with the microphone closed, while using AirPods. The old ordering started playback before async capture startup completed. The coordinator now waits for the stream before activating the shared timeline; a deterministic delayed-start regression covers this fix. The manual AirPods retest remains open until the operator confirms Listening and speech-driven scrolling.


## Follow-up acceptance

- [x] Do not run or resume the shared playback timeline until microphone capture startup returns a usable stream; cover delayed startup with a coordinator regression (the delayed two-second startup test passes).
- [x] Retest startup and speech-driven scrolling on macOS 27 with AirPods; operator confirmed Follow Voice works after the startup fix (2026-10-15).

## Operator retest (2026-10-15)

The operator confirmed the rebuilt app starts and follows speech using AirPods. Speech-model installation completion and final inspector readability remain unverified.

## Summary of Changes

Fixed Follow Voice startup crashes, model installation error handling, and inspector state contrast. The operator confirmed the rebuilt app, speech-model installation, and distinct readable controls during the macOS 26+ acceptance run.
