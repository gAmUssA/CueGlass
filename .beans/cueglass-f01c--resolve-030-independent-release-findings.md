---
# cueglass-f01c
title: Resolve 0.3.0 independent release findings
status: completed
type: bug
priority: normal
created_at: 2026-10-17T05:10:50Z
updated_at: 2026-10-17T19:57:03Z
---

Continue original cueglass-tgvc correction1; related voice work cueglass-6nk0. Independent reports: /Users/vikgamov/.local/state/cueglass/release-030/reports/reviewer.md and tester.md.

- [x] R1/T3 actual microphone routing and errors — `VoiceCaptureRouter` selects the default explicitly, reads the route back, reports refusal and fallback; coordinator and inspector show it.
- [x] R2/T4 startup/reconfiguration single tap ownership — one owner; a change during analyzer preparation is folded into the first tap.
- [x] R3 Collapse manual priority — `takeManualControl` cancels pending/spoken-paused voice and closes capture before parking.
- [x] R4/T1 island controls — Core `controlsBandReserve` keeps the band beside the housing in the tray, frame and mask; every control gets a frame.
- [x] T2 calibrated preview follows the live Dock reflection and guide; caption agrees.
- [x] R5/R6 ADR 0013 supersedes the 0007 configuration-change clause (0007 restored to its accepted text); M1/M8/M13/M15 reconciled, M18 and microphone rows added.
- [x] Regressions shown failing without each fix; Core, native, strict format, beans check, diff check green; pushed for independent verification.
Owner hardware rows (M15/M16/M18, microphone rows) and the macOS 14 runtime check beyond the three accepted r11 observations moved to cueglass-feeg on 2026-10-17.

Owner passed r11 notch attachment/animation, main preview and microphone selection/switching; other observations remain unverified. No PR/merge/release in corrective developer assignment.

## Correction 2 from final independent verification

At release candidate d5a262c (implementation95f761e), both independent reports reproduce two residual defects. Continue original cueglass-tgvc correction2, preserving its base and budget.

- [x] F1: consume latest microphone choice across every startup format retry before installing the tap; cover repeated changes and cancellation.
- [x] F2: keep parked Play/Adjust full-size and hittable for supported wider housing at minimum width and all nudges.
- [x] Fold advisory shortcut tooltip and scoped owner-acceptance bookkeeping into this necessary correction.
- [x] Demonstrate regressions before/after, run relevant/full gates, commit and push for independent final verification.

Reports: /Users/vikgamov/.local/state/cueglass/release-030/final/reviewer.md and tester.md. Lead independently confirmed probes. Owner three r11 passes remain accepted; unmentioned hardware release criteria remain separate.



## Correction 3 — Copilot review on PR #5 (2026-10-17)

The exact candidate a8ac7c6b6121d5bf4078e9b6aec9798701856f7c passed PR CI, but Copilot review 5558087329 identified eight concrete release-blocking defects. Track these independent PR blockers as separate task cueglass-f01c; preserve cueglass-tgvc's two completed corrections and original scope unchanged. Preserve PR #5 and its 0.3.0/build3 metadata.

- [x] 4302916661 — reload per-display Camera Dock preferences when the display picker changes; prevent stale values being persisted to the newly selected display.
- [x] 4302916715 — Stop Take restores the pre-Dock Preview size while clearing the prior surface and play state.
- [x] 4302916757 — if the saved return display is unavailable, recover to paused Preview with the saved logical size and anchor.
- [x] 4302916781 — capture the active Output display as the Dock return target, independently from the next selected destination.
- [x] 4302916815 — update live Dock text-panel visibility for non-layout background edits and undo without rebuilding layout.
- [x] 4302916862 — use a shared audio-time base for silence and spoken-pause resume across microphone recovery gaps.
- [x] 4302916901 — limit old-default width migration to legacy catalog entries; preserve current saved widths at slider stops.
- [x] 4302916924 — allow the selected mirrored built-in display fallback and align geometry tests with ADR 0012.
- [x] Add deterministic native/core regression tests for all eight findings, run full Core/native/format/Beans/diff gates, commit and push the correction to release/cueglass-030.
- [x] Obtain full independent reviewer and tester passes on the corrected full branch tip; then re-request Copilot and pass new exact-head CI before release resumes. Full independent review at 4f952f4 (review 5559175501) and scoped re-check PASS at e021d43 (review 5559397563); Copilot reviews 5558794956, 5559273824 and 5559388091; exact-head CI 39057584583 success; merged as 80d23b81f641164eeaff695169e791637cb9db93.

Full Copilot artifacts: /Users/vikgamov/.local/state/cueglass/release-030/copilot-reviews.json and copilot-inline-comments.json. Release report: /Users/vikgamov/.local/state/cueglass/release-030/release-report.md. Hardware/Mac14 runtime rows remain deferred and unverified per owner scope decision.

### Correction 3 implementation (2026-10-17)

Display picker edits route through `selectDisplay`, which reloads the target display's Dock values first. Stop Take converts the saved return surface into a Preview return at the pre-Dock size. The Output return checks the saved display against the current display list and falls back to paused Preview at the saved size and anchor; the return target is the active Output's own display id. Non-layout style edits and their undo call the Dock controller's `updateAids`, which refreshes the text-panel decision without a relayout. The coordinator reads one captured-audio clock from the source (`capturedAudioTime`, the AudioInputPipe sample clock) for silence detection and spoken-pause resume, with host time only as a fallback. The preference catalog marks entries written by current builds and migrates only unmarked legacy entries. Display selection accepts the selected mirrored built-in display; ADR 0012 records the retained contract. Regressions: three Core tests (catalog, selection), five native OperatorFeatureTests and one VoiceFollowTests test, each shown failing on the prior source and passing after. Hardware/macOS 14 rows remain unverified.

## Summary of Changes

All three correction rounds shipped in PR #5 (merge 80d23b81f641164eeaff695169e791637cb9db93) and in the v0.3.0 prerelease (run 39061330997): microphone routing and single tap ownership, Collapse manual priority, island controls, calibrated preview, ADR 0013, the two residual defects from the final verification, and the eight Copilot findings on a8ac7c6, each with regressions shown failing on the prior source. Hardware and macOS 14 rows beyond the owner's accepted r11 observations are tracked in cueglass-feeg.
