---
# cueglass-ssfp
title: Apply a pending microphone selection before a startup format wait gives up
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T17:14:16Z
updated_at: 2026-10-17T17:20:45Z
parent: cueglass-aeqt
---

N2 from the independent final5 review of PR #5: VoiceCaptureRouter.usableInputFormat retries the current device up to formatAttempts and throws microphoneFormatUnavailable without reading pendingReconfiguration. A microphone chosen in the picker during a retry sleep while the current device never yields a usable format is ignored; open() and goLive() fail and capture stops even though the chosen device would have produced a format. Before treating the format as unavailable, consume pendingReconfiguration, apply that route and keep waiting within the existing formatAttempts and startupReconfigurationBudget, in both open() and goLive(). Do not raise either budget; do not change live reconfiguration or refusal reporting. Evidence: /Users/vikgamov/.local/state/cueglass/release-030/final5/reviewer.md (N2).

- [x] Add regressions where device A never yields a usable format for more than formatAttempts reads, B is selected during the first retry sleep, and both open() and goLive() finish on B with one installed tap and no second installer.
- [x] Consume pendingReconfiguration before treating the startup format as unavailable, in open() and goLive(), within the existing formatAttempts and startupReconfigurationBudget.
- [x] Run the Core and native suites, strict formatting, Beans integrity, diff check and the universal unsigned ReleaseLocal build with checksum.
- [ ] Commit and push, then fast-forward release/cueglass-030 for independent exact-tip verification.

## Correction — 2026-10-17

`open()` and `goLive()` now wait through `startupFormat(passes:)`, which catches `microphoneFormatUnavailable` while a reconfiguration is pending and restarts the wait on the newly applied route. Every wait, including a restart, counts against the caller's `startupReconfigurationBudget`, so neither budget is raised; `formatAttempts` per wait is unchanged. Live `reconfigure()` still uses the plain wait and refusal reporting is untouched. Two regressions (open and goLive, built-in never usable, USB chosen on the first retry sleep) throw `microphoneFormatUnavailable` on the prior source and finish on USB with one installed tap after the change; the existing startup-wait tests keep passing.
