---
# cueglass-mpqt
title: Publish CueGlass 0.2.0 GitHub release
status: in-progress
type: task
priority: normal
created_at: 2026-10-16T02:41:48Z
updated_at: 2026-10-16T03:41:48Z
parent: cueglass-aeqt
---

Prepare, merge, build, and publish CueGlass 0.2.0 through the public GitHub Actions release workflow. Keep signing, notarization, and iCloud deferred.

## Checklist

- [x] Resolve local native test discrepancy and pass verification
- [x] Prepare version 0.2.0 changelog and commit Bean updates
- [x] Resolve valid review findings with deterministic regression coverage
- [ ] Obtain current independent review and green CI, then merge
- [ ] Verify main CI and publish v0.2.0 unsigned/unnotarized GitHub release
- [ ] Verify release assets and workflow result; record evidence


## Review follow-up

- Hoisted UTF-16 source-length calculation out of TextKit fragment enumeration to keep long-script layout measurement linear.
- The existing 100,000-word native measurement fixture covers the affected path.

## Current review gate

- Fixed the reviewed capture lifecycle, volatile jump, low-confidence command, pending start and locale, playback baseline, finalized pace, command resume, and sentence-index findings. Added deterministic tests; refresh Copilot on the pushed head before merge.

## Local verification

- `swift test --package-path Packages/CueFlowCore`: 68 tests passed.
- `bash scripts/test-app.sh`: 91 tests passed, including voice lifecycle and playback regressions.
- `xcrun swift-format lint --strict --recursive ...`: passed.
- `beans check` and `git diff --check`: passed.

## Latest review follow-up

- Fixed six additional Copilot findings: correlate pace only with finalized alignment progress; retain all same-range words while deduplicating replayed batches; clear queued ordinary-play intents when Follow Voice supersedes measurement; recheck the voice epoch after command-pause awaits; retain pace anchors across same-line/subthreshold samples; and count nearby repeated script passages as competing reacquisition paths.
- `swift test --package-path Packages/CueFlowCore`: 72 tests passed.
- `bash scripts/test-app.sh`: 94 tests passed, including command-pause, queued-start, finalization/pace, and voice-lifecycle regressions.
- Strict Swift formatting, `beans check --json`, and `git diff --check` passed.
- Next: commit/push these fixes, refresh Copilot review and GitHub CI on the exact head, then merge and publish v0.2.0.

## GitHub CI correction

- The first macOS run exposed a timing race in `volatileDistantSpeechWaitsForFinalizationBeforeSeeking`: a fixed 200-yield loop could finish before the async capture worker applied the finalized result on a loaded runner.
- Replaced the tight loop with a bounded 2-second wait that yields through 5 ms sleeps and the main queue while checking the playback anchor.
- `bash scripts/test-app.sh`: all 94 tests passed locally after the change. GitHub must rerun CI on the pushed correction.
