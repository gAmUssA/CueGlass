---
# cueglass-mpqt
title: Publish CueGlass 0.2.0 GitHub release
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:41:48Z
updated_at: 2026-10-16T04:10:34Z
parent: cueglass-aeqt
---

Prepare, merge, build, and publish CueGlass 0.2.0 through the public GitHub Actions release workflow. Keep signing, notarization, and iCloud deferred.

## Checklist

- [x] Resolve local native test discrepancy and pass verification
- [x] Prepare version 0.2.0 changelog and commit Bean updates
- [x] Resolve valid review findings with deterministic regression coverage
- [x] Obtain current independent review and green CI, then merge
- [x] Verify main CI and publish v0.2.0 unsigned/unnotarized GitHub release
- [x] Verify release assets and workflow result; record evidence


## Review follow-up

- Hoisted UTF-16 source-length calculation out of TextKit fragment enumeration to keep long-script layout measurement linear.
- The existing 100,000-word native measurement fixture covers the affected path.

## Current review gate

- Fixed the reviewed capture lifecycle, volatile jump, low-confidence command, pending start and locale, playback baseline, finalized pace, command resume, and sentence-index findings. Added deterministic tests; the final Copilot review on 32c8374 reported zero open findings.

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
- The final fixes were committed as `32c8374`; fresh Copilot and CI passed on that head, then PR #4 merged and v0.2.0 was published (evidence below).

## GitHub CI correction

- The first macOS run exposed a timing race in `volatileDistantSpeechWaitsForFinalizationBeforeSeeking`: a fixed 200-yield loop could finish before the async capture worker applied the finalized result on a loaded runner.
- Replaced the tight loop with a bounded 2-second wait that yields through 5 ms sleeps and the main queue while checking the playback anchor.
- `bash scripts/test-app.sh`: all 94 tests passed locally after the change. The subsequent PR and push workflows passed on the updated release head.

## Additional Copilot review follow-up

- Addressed four previously missed findings from the full review body: safe display-stall pause time now stays at the last presented frame; rejected momentum cannot suspend Follow Voice; resuming resets the scrub gate; and final transcript ranges replace only overlapping volatile words while newly finalized speech remains time-ordered.
- Added deterministic app regressions for voice stall position/elapsed time, rejected momentum, and resume after scrub; added a core regression for incremental final-range prefix preservation.
- Fresh Copilot and PR/push workflows passed on `32c8374`; merge and main verification are recorded below.

## Local verification after additional review fixes

- `swift test --package-path Packages/CueFlowCore`: 73 tests passed.
- `bash scripts/test-app.sh`: 97 tests passed, including display-stall safe pause and stale-momentum regressions.
- Strict Swift formatting, `beans check --json`, and `git diff --check` passed.
- Both PR and push workflows passed on `32c8374`; main CI passed on merge commit `0df1d56`, including tests, strict formatting, and universal packaging.

## Merge evidence

- PR #4 merged at `0df1d5655dd10e7c591c1520af51d21e68e3d688`.
- The exact PR head passed both pull-request and push macOS workflows, including 73 core tests, 97 native app tests, strict formatting, and universal unsigned packaging.
- Fresh Copilot review on the exact head reported zero open findings; one medium transcript-window edge case is deferred for follow-up.
- The repository has no `review-codex.yml` workflow, so the Codex policy review lane was unavailable.

## Summary of Changes

Merged [PR #4](https://github.com/gAmUssA/CueGlass/pull/4) as `0df1d5655dd10e7c591c1520af51d21e68e3d688`. Main CI passed 73 core tests, 97 native app tests, strict formatting, universal unsigned build, and package verification. Published the [v0.2.0 unsigned/unnotarized prerelease](https://github.com/gAmUssA/CueGlass/releases/tag/v0.2.0) through [workflow run 38848603800](https://github.com/gAmUssA/CueGlass/actions/runs/38848603800).

Verified the downloadable ZIP against SHA-256 `a722252bfd183ba97c66472f87ef06882be66556469cfeb0677ab5e0ec45907c`, confirmed archive integrity and universal `x86_64 arm64` binary, and checked the included `UNNOTARIZED.txt`. Deferred a medium spoken-command transcript-window edge case to follow-up Bean `cueglass-2k8v`.
