---
# cueglass-jxkr
title: Add spoken transport commands to Follow Voice
status: in-progress
type: task
priority: normal
created_at: 2026-10-15T15:16:36Z
updated_at: 2026-10-15T22:47:35Z
parent: cueglass-2mil
---

Add opt-in spoken transport controls to Follow Voice, initially covering Pause, Resume, Stop Following, and Stop Take. Reuse existing PlaybackSession/OperatorWindowController actions, preserve manual-control priority, and prevent script text from accidentally issuing commands. Add deterministic command-phrase parsing and coordinator tests, document command behavior and manual verification. Commands accept either CueGlass (including the split Cue Glass transcript) or Prompter as the English wake phrase and resolve at finalization or after unchanged wording remains stable briefly; known low-confidence words are rejected, and unavailable confidence is treated as unknown. Either wake phrase plus stop maps to Stop Following.


## Acceptance

- [x] Parse prefixed commands at finalization or after 0.75 seconds of unchanged wording; reject known low confidence, allow unavailable confidence, replace revised volatile wording, and bound transient state.
- [x] Implement Pause/Resume with capture retained only while waiting for a spoken Resume; Stop Following and Stop Take use existing controller actions.
- [x] Preserve manual-control priority and prevent command speech from driving script alignment.
- [x] Add deterministic parser and coordinator tests, update UI help and architecture/manual verification docs.
- [x] Build and run automated checks.
- [x] Record human macOS 26+ Pause/Resume command verification.
- [ ] Record human macOS 26+ Stop Following/Stop Take and false-positive checks.


## Verification (2026-10-15)

- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 56 tests passed.
- `scripts/test-app.sh`: all VoiceFollow tests passed. The full 81-test app bundle retains two failures in the separate display reconnection test `displaySelectionRemapsWhenDisplayIDChanges`.
- Human command verification remains pending after relaunching the rebuilt DebugLocal app.


## Live command follow-up

The operator reports that spoken commands still do not trigger in the rebuilt app. Verify the common short form “CueGlass, stop” (Stop Following) and add stable-phrase fallback when the SpeechTranscriber finalization watermark does not advance. Keep the existing pending human macOS 26+ verification open.

- [x] Recognize CueGlass stop as Stop Following and safely resolve stable exact prefixed phrases when finalization is delayed or omitted.
- [x] Request SpeechTranscriber's alternative interpretations and use up to three for command matching while keeping script following on the best transcript.


## Verification (2026-10-15 follow-up)

- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 59 tests passed.
- `scripts/test-app.sh`: build-for-testing succeeded and all VoiceFollow tests passed; the 81-test app run has two assertions failing only in `OperatorFeatureTests.displaySelectionRemapsWhenDisplayIDChanges`.
- Strict Swift formatting and `beans check --json` passed before alternative-interpretation follow-up.
- Rebuilt DebugLocal app is at `.build/Xcode/Build/Products/DebugLocal/CueFlow.app`. Human speech-command retest remains pending.

## Alternative interpretation follow-up (2026-10-15)

- Operator confirms normal script speech follows correctly but transport commands remain unrecognized; the exact ASR phrase is not logged or retained.
- Command matching now checks the best transcript and up to three alternative interpretations. Script alignment remains based on the best transcript only.
- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 60 tests passed, including recovery when an alternative contains the correct wake phrase.
- `xcodebuild ... -only-testing:CueFlowTests/VoiceFollowTests test`: 25 tests passed.
- DebugLocal arm64 app and test bundle build successfully with deployment target macOS 14.
- Human retest is still required.

## Incremental command-channel follow-up

- [x] Retain up to three bounded command-only hypotheses across separate ASR updates and add deterministic regression coverage.
- [x] Record the contextual command-recognition architecture and verification results.
- [x] Rebuild the app for a fresh macOS 26+ human command retest (human acceptance remains open).

## Incremental command-channel verification (2026-10-15)

- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 64 tests passed.
- `xcodebuild ... -only-testing:CueFlowTests/VoiceFollowTests test`: 26 tests passed, including incremental command-only handling.
- DebugLocal arm64 app build succeeded for `arm64-apple-macos14.0`.
- Strict Swift format, `beans check --json`, and `git diff --check` passed.
- The operator's previous app process was still running after the rebuild. Quit that older instance and launch `.build/Xcode/Build/Products/DebugLocal/CueFlow.app` to test the new build. Human macOS 26+ command verification remains open.


Architecture decision: [ADR 0010](../docs/adr/0010-contextual-command-recognition-channel.md).


The latest build includes three independent command hypotheses and per-transcriber finalization clocks. `swift test` passes 64 Core tests; the focused native VoiceFollow suite passes 26 tests; the arm64 DebugLocal build passes with macOS 14 deployment. The currently running CueGlass process predates this build, so restart it before the live command retest.

## Human verification (2026-10-15)

- The operator confirmed prefixed Pause and Resume work in the rebuilt app and Follow Voice behaves as expected.
- Stop Following, Stop Take, and false-positive resistance have not been separately confirmed; those manual checks remain pending.

## Current candidate verification (2026-10-15)

- Core suite: 64 tests passed; focused native VoiceFollow suite: 26 passed; full DebugLocal native suite: 82 passed.
- Pause/Resume passed operator retest. Stop Following, Stop Take, and false-positive resistance remain pending.


## Operator retest update (2026-10-15)

The operator now confirms that spoken command recognition works in the rebuilt app. Pause/Resume was already confirmed. Stop Following and Stop Take outcomes, and false-positive resistance, remain open pending direct checks.


## Candidate CI result (2026-10-15)

GitHub Actions run [38802743545](https://github.com/gAmUssA/CueGlass/actions/runs/38802743545) passed the Core/native tests and strict formatting on candidate commit `eed609b`. The operator confirms command recognition works; exact Stop Following/Stop Take outcomes and false-positive resistance remain pending.

## Wake phrase update (2026-10-15)

- [x] Accept CueGlass/Cue Glass and Prompter as exact prefixes for the existing command set; add parser tests, inspector help and ADR/design/changelog documentation.
- [x] Verify CueGlass and Prompter prefix recognition in live human speech (operator confirmed both on 2026-10-15).
- [ ] Verify Stop Following versus Stop Take outcomes in live human speech.
- [ ] Verify false-positive resistance with unprefixed command words and ordinary script speech in live human speech.

## Wake phrase verification (2026-10-15)

- `swift test --package-path Packages/CueFlowCore --scratch-path .build/core`: 64 tests passed, including CueGlass/Prompter command variants and short-stop waiting behavior.
- `scripts/test-app.sh`: 82 native tests passed. Universal unsigned ReleaseLocal build passed for arm64 and x86_64 at macOS 14.0 minimum, version 0.2.0/build 2.
- `xcrun swift-format lint --strict --recursive CueFlow Packages`, `beans check --json`, and `git diff --check` passed.
- The operator has now confirmed both CueGlass and Prompter prefixes are recognized. Exact Stop Following/Stop Take outcomes and false-positive resistance remain open.

## GitHub Actions follow-up (2026-10-15)

Run [38809174552](https://github.com/gAmUssA/CueGlass/actions/runs/38809174552) passed on commit `2f59c50`: Core/native tests, strict formatting, universal unsigned build, and release asset packaging. The tag-only upload was skipped. The operator has now confirmed both CueGlass and Prompter prefixes are recognized. Stop Following/Stop Take outcomes and false-positive resistance remain open.

## Live wake-phrase verification (2026-10-15)

The operator tested the CueGlass prefix and the Prompter prefix and reports that both are recognized. This confirms prefix recognition; the specific Stop Following/Stop Take results and false-positive resistance remain unverified.

## Candidate follow-up (2026-10-15)

The operator confirms that both CueGlass and Prompter wake phrases are recognized. Candidate `2c3c25761ea5ea8296efcc341abd2de444476039` passed CI run 38816562330 and a full independent review with no blockers. The controller regression for Play/Space resume during spoken Pause passes; live Play/Space confirmation, exact Stop Following/Stop Take outcomes, and false-positive resistance remain open.
