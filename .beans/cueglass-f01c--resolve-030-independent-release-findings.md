---
# cueglass-f01c
title: Resolve 0.3.0 independent release findings
status: in-progress
type: bug
created_at: 2026-10-17T05:10:50Z
updated_at: 2026-10-17T06:40:00Z
---

Continue original cueglass-tgvc correction1; related voice work cueglass-6nk0. Independent reports: /Users/vikgamov/.local/state/cueglass/release-030/reports/reviewer.md and tester.md.

- [x] R1/T3 actual microphone routing and errors — `VoiceCaptureRouter` selects the default explicitly, reads the route back, reports refusal and fallback; coordinator and inspector show it.
- [x] R2/T4 startup/reconfiguration single tap ownership — one owner; a change during analyzer preparation is folded into the first tap.
- [x] R3 Collapse manual priority — `takeManualControl` cancels pending/spoken-paused voice and closes capture before parking.
- [x] R4/T1 island controls — Core `controlsBandReserve` keeps the band beside the housing in the tray, frame and mask; every control gets a frame.
- [x] T2 calibrated preview follows the live Dock reflection and guide; caption agrees.
- [x] R5/R6 ADR 0013 supersedes the 0007 configuration-change clause (0007 restored to its accepted text); M1/M8/M13/M15 reconciled, M18 and microphone rows added.
- [x] Regressions shown failing without each fix; Core, native, strict format, beans check, diff check green; pushed for independent verification.
- [ ] Owner hardware rows (M15/M16/M18, microphone rows) with device details; macOS 14 runtime.

Owner passed r11 notch attachment/animation, main preview and microphone selection/switching; other observations remain unverified. No PR/merge/release in corrective developer assignment.
