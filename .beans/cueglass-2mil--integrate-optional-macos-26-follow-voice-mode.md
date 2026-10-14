---
# cueglass-2mil
title: Integrate optional macOS 26 Follow Voice mode
status: in-progress
type: feature
priority: normal
created_at: 2026-10-14T17:12:48Z
updated_at: 2026-10-14T23:43:47Z
---

Add optional real-time speech-following to CueGlass using the standalone VoiceFollowCore and Apple's SpeechAnalyzer/SpeechTranscriber on macOS 26+. Keep the app's macOS 14 deployment target; gate the new API and UI by availability. Request microphone access only after an explicit Follow Voice action, show listening/stop state, process audio without retaining it, and handle model support/installation deliberately. Map aligned script token offsets through TextKit 2 into the shared PlaybackSession with smooth bounded motion and manual-control priority. Preserve Timed Scrolling and existing behavior on macOS 14–25. Add deterministic tests for mapping and drive policy, and document/run manual fresh-permission human-speech validation on macOS 26+. See docs/design/speech-following.md and the standalone Experiments/VoiceFollow prototype.


- [x] Add macOS 26 SpeechAnalyzer capture adapter and explicit microphone permission flow.
- [x] Add locale/model readiness, consented installation progress, listening state, and no-retention behavior.
- [x] Map immutable script UTF-16 token ranges through TextKit 2 into the shared playback drive.
- [x] Add smooth bounded follow motion with silence hold, reacquisition, and manual-control priority.
- [x] Add deterministic mapping, playback, scenario and fake-source tests.

## Verification

- [x] Update speech-following research, implementation status, manual test plan, iCloud setup, and accepted ADR 0007.
- [x] Run macOS 14-target DebugLocal build, Core/native tests, strict Swift formatting, Beans consistency and repository checks. iCloud configuration build is conditional; owner Info-iCloud.plist and Owner.xcconfig are absent in this worktree.
- [ ] Run the documented macOS 26+ live human-speech acceptance matrix. The operator can participate once code and build gates are stable; no synthetic speech is substituted.

- [x] Prevent Follow Voice activation from surviving Stop or manual input while layout, readiness, or microphone permission is pending; add deterministic cancellation regressions.

- [x] Make the pre-macOS-26 availability test deterministic on macOS 26+ and verify both unsupported and supported version outcomes.
- [x] Fix the SpeechVoiceSource Swift 6 sendability errors under CI Xcode 26.6 while preserving the macOS 14 target and no-audio-retention behavior.
