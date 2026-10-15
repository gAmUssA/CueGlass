---
# cueglass-q82s
title: Stabilize Follow Voice startup and inspector feedback
status: in-progress
type: bug
priority: high
created_at: 2026-10-15T14:26:25Z
updated_at: 2026-10-15T14:40:02Z
parent: cueglass-2mil
---

User-reported macOS 27 DebugLocal problems (2026-10-15): explicit speech-model installation ends in a generic failure message; pressing Start Follow Voice crashes CueFlow; Follow Voice labels and controls have weak contrast and unclear enabled/disabled state. Diagnose the captured crash reports and Speech asset installation error, fix the underlying issues with deterministic regression coverage, improve inspector readability/state cues, then rebuild and document remaining operator speech checks.


## Acceptance

- [x] Isolate and correct the AVAudioEngine tap actor-isolation crash from the 2026-10-15 macOS crash reports.
- [x] Make model-install errors actionable, handle already-complete/racing installations, and retain an explicit retry path.
- [x] Improve Follow Voice status contrast and make disabled, ready, installing, listening, denied, paused, and failed states visually distinct.
- [x] Add deterministic regression coverage for the audio callback and model-install state/error behavior.
- [x] Rebuild the macOS 14 target, rerun Core/native tests and strict formatting, and refresh the manual-test documentation.
- [ ] Retest model installation, app startup, and inspector readability on macOS 27 after the operator retries the rebuilt app.

## Current Evidence (2026-10-15)

The two Start crashes were Swift actor-isolation traps on AVAudioEngine’s realtime messenger queue. The tap callback is now a file-level Sendable handler and its background-queue regression passes. The model installer now exposes the OS error, handles the AssetInventory downloading and already-installed states, and provides a check/retry route. DebugLocal builds for macOS 14; 41 Core and 74 native tests pass; strict formatting and beans consistency pass. Operator retry of the real model download, Start action, and updated contrast remains pending.
