---
# cueglass-2mil
title: Integrate optional macOS 26 Follow Voice mode
status: in-progress
type: feature
priority: normal
created_at: 2026-10-14T17:12:48Z
updated_at: 2026-10-15T21:40:37Z
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
- [ ] Complete the remaining documented macOS 26+ human-speech acceptance matrix. The operator has confirmed AirPods speech following, prefixed Pause/Resume, and faster adaptive pace; all other required scenarios remain pending. No synthetic speech is substituted.

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

- On macOS 27.0.1, the app inspector confirms Language English (United States) and says the selected Apple speech model needs installation consent, with an explicit Install Speech Model button. The read-only runtime reports SpeechTranscriber available and `en_US` in supported/installed locale sets, while AssetInventory for the configured `en-US` module is `.supported` (assets need download). No installation or microphone capture has been started.
- Microphone permission was reset for DebugLocal bundle `com.example.cueflow` to prepare a fresh prompt. The prompt and any allow/deny result remain pending until an explicit Start action.

## 0.2.0 candidate verification (2026-10-15)

- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 64 tests passed.
- Focused `CueFlowTests/VoiceFollowTests`: 26 tests passed; the full DebugLocal native suite now passes all 82 tests after making the display reconnection regression independent of persisted selection state.
- Strict Swift formatting, `beans check --json`, and `git diff --check` pass. Current host is macOS 27.0.1; the app/test bundle targets macOS 14.0. A universal ReleaseLocal build, direct `scripts/test-app.sh` run, current-tip independent review, and CI on the release candidate remain outstanding.
- Human confirmation is partial: AirPods speech following, prefixed Pause/Resume, and pace adjustment work. Stop Following, Stop Take, false-positive resistance, slow/silence pace recovery, permission denial/model completion, silence/ad-libs/skips/rereads, manual takeover, Timed Scrolling separation, and a sustained-take/teardown test remain open.


## Candidate recheck (2026-10-15)

- Current local 0.2.0/build 2 candidate: `scripts/test-app.sh` passed all 82 native tests; `swift test --package-path Packages/CueFlowCore --scratch-path .build/core` passed all 64 Core tests.
- Strict Swift format, `beans check --json`, and `git diff --check` pass. The unsigned universal ReleaseLocal app verifies arm64+x86_64, macOS 14.0 minimum, version 0.2.0/build 2, and microphone usage text; the local unsigned/unnotarized ZIP checksum and `unzip -t` pass.
- The operator confirms spoken command recognition works in the rebuilt app. Exact Stop Following/Stop Take behavior and the remaining human acceptance matrix are still pending.
- CI and an independent full review have not run on the current local candidate. Do not mark this feature complete until the required human checks and exact-candidate release gates finish.


## GitHub Actions verification (2026-10-15)

Commit `eed609beb43a0a972ad3a3819df116ad3b7459be` passed workflow run [38802743545](https://github.com/gAmUssA/CueGlass/actions/runs/38802743545): Core and native tests, strict Swift formatting, universal unsigned build, and release asset verification. The tag-only publishing step was skipped. Human acceptance and the independent full review remain incomplete.

## 0.2.0 follow-up status (2026-10-15)

The operator approved Prompter as an alternative command wake phrase. The implementation already supports it; the UI, docs, ADR, changelog, and deterministic tests now state that contract. Core tests (64), native app tests (82), strict formatting, Beans checks, and an unsigned universal ReleaseLocal build passed. GitHub Actions run 38809174552 passed on commit 2f59c50. The prior full review report was unaccepted because its required delivery marker did not match the brief; a valid current-tip full independent review remains outstanding. Human acceptance remains open for model download/permission-denial recovery, exact Stop actions/false positives, silence/ad-libs/skips/rereads, manual takeover, Timed Scrolling, pace recovery, and a sustained take/teardown.

## Operator wake-phrase verification (2026-10-15)

The operator tested both CueGlass and Prompter prefixes and reports that both are recognized. This confirms wake-phrase recognition only; exact Stop Following/Stop Take outcomes and false-positive resistance remain open, along with the other pending human-speech scenarios.
