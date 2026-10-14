---
# cueglass-2mil
title: Integrate optional macOS 26 Follow Voice mode
status: todo
type: feature
priority: normal
created_at: 2026-10-14T17:12:48Z
updated_at: 2026-10-14T17:12:51Z
---

Add optional real-time speech-following to CueGlass using the standalone VoiceFollowCore and Apple's SpeechAnalyzer/SpeechTranscriber on macOS 26+. Keep the app's macOS 14 deployment target; gate the new API and UI by availability. Request microphone access only after an explicit Follow Voice action, show listening/stop state, process audio without retaining it, and handle model support/installation deliberately. Map aligned script token offsets through TextKit 2 into the shared PlaybackSession with smooth bounded motion and manual-control priority. Preserve Timed Scrolling and existing behavior on macOS 14–25. Add deterministic tests for mapping and drive policy, and document/run manual fresh-permission human-speech validation on macOS 26+. See docs/design/speech-following.md and the standalone Experiments/VoiceFollow prototype.


- [ ] Add macOS 26 SpeechAnalyzer capture adapter and explicit microphone permission flow.
- [ ] Add locale/model readiness, consented installation progress, listening state, and no-retention behavior.
- [ ] Map immutable script UTF-16 token ranges through TextKit 2 into the shared playback drive.
- [ ] Add smooth bounded follow motion with silence hold, reacquisition, and manual-control priority.
- [ ] Add deterministic tests and run the documented macOS 26+ live human-speech validation.
