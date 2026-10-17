---
# cueglass-nj97
title: Resolve fresh CueGlass 0.3.0 release blockers
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T14:56:08Z
updated_at: 2026-10-17T15:10:22Z
parent: cueglass-aeqt
---

Resolve four source-correctness issues found by Copilot on PR #5 at a059bce903e9f02d2a7eae2eff0849dd400e87e3: synchronize AudioInputPipe.nextSampleTime access, keep failed Camera Dock Output recovery paused, show Load Latest errors during pending work, and validate attached Dock height against its resolved attached geometry. Add focused deterministic regressions, update release tracking, run full local gates, commit and push to fix/cueglass-030-followup for independent verification; no PR, merge, tag, or publication in this assignment. The user authorized merging, building, and releasing CueGlass 0.3.0 through GitHub; no signing/notarization or unrelated changes.

## Developer checklist

- [x] Reproduce and fix synchronized audio sample timestamps with regression coverage.
- [x] Reproduce and fix both failed Output recovery paths with regression coverage.
- [x] Reproduce and fix pending-revision error presentation with regression coverage.
- [x] Reproduce and fix attached Dock height validation with regression coverage.
- [ ] Run configured gates, update release tracking, and commit correction series.
- [ ] Push the correction branch and record handoff evidence.

## Verification evidence

Audio sample clock: Thread Sanitizer reproduced the original Swift access race between append and audioTime. The fixed test passes with 64 contiguous 512-frame buffers, concurrent clock reads, and converter replacement; source yields outside the lock.

Output recovery: both missing-display and disappeared-during-reopen paths reproduced a queued resume. The regression now passes with no countdown/resume, preserved snapshot/anchor/layout, and the disconnect notice after measurement. Existing successful restoration also passes.

Load Latest: the pending footer formerly suppressed the downloading/retry status. The controller regression preserves the pending flag and immutable take while the footer now exposes the same recovery message both with and without a pending revision; routine Paused remains filtered.
