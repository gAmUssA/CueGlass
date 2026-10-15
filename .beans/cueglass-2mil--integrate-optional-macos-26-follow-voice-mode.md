---
# cueglass-2mil
title: Integrate optional macOS 26 Follow Voice mode
status: in-progress
type: feature
priority: normal
created_at: 2026-10-14T17:12:48Z
updated_at: 2026-10-15T01:17:58Z
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
- [ ] Run the documented macOS 26+ live human-speech acceptance matrix. Code and CI gates now pass; the operator-led macOS 26+ human-speech matrix is still pending. No synthetic speech is substituted.

- [x] Prevent Follow Voice activation from surviving Stop or manual input while layout, readiness, or microphone permission is pending; add deterministic cancellation regressions.

- [x] Make the pre-macOS-26 availability test deterministic on macOS 26+ and verify both unsupported and supported version outcomes.
- [x] Fix the SpeechVoiceSource Swift 6 sendability errors under CI Xcode 26.6 while preserving the macOS 14 target and no-audio-retention behavior.


## Final source-review corrections

- [x] Pause the shared timeline after manual seek, step, pace, or reverse input during Follow Voice; require Play/Space or Resume Following before motion resumes.
- [x] Keep Follow Voice suspended and paused across preview/output/floating surface and floating-resize layout changes; preserve ordinary non-voice auto-resume and Timed Scrolling behavior.
- [x] Add clock-advanced regressions for manual and surface transitions, then rerun the full verification gates.
- [x] Preserve model readiness and permission state after Stop Take instead of presenting Start when the selected model is unavailable.
- [x] Update documented native test totals from 63 to 70.

## Latest verification (2026-10-14)

- Corrected tip: `cce977e56fdd7e51d51319c36c824dec4a03683f`; a fresh unsigned DebugLocal rebuild succeeded for `arm64-apple-macos14.0`.
- Local deterministic suites passed: 41 Core tests and 70 native tests. Strict formatting, repository/plist checks, and `beans check` passed.
- GitHub Actions run [38661758289](https://github.com/gAmUssA/CueGlass/actions/runs/38661758289) passed the exact tip, including tests, formatting, and the unsigned universal build; release publishing was skipped.
- A fresh scoped independent review cleared B1/B2/A1/A2 with no new blocker. It is not the full review required before release.
- The macOS 26+ human-speech acceptance matrix remains pending and must be completed from observed permission, model, silence, ad-lib, skip, reread, manual-control, Timed Scrolling, sustained-take, and teardown behavior.

- Read-only macOS 27.0.1 preflight found SpeechTranscriber available; supported and installed locale sets include `en_US`. The configured `en-US` module reports AssetInventory `.supported` (download required). The in-app inspector still needs confirmation; no model was installed.
- Microphone permission was reset for DebugLocal bundle `com.example.cueflow` to prepare a fresh prompt. The prompt and any allow/deny result remain pending until an explicit Start action.
