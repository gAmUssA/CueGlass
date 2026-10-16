---
# cueglass-tgvc
title: Fix Camera Dock fit rejection on notched MacBook
status: in-progress
type: bug
priority: high
created_at: 2026-10-16T18:28:24Z
updated_at: 2026-10-16T18:38:03Z
parent: cueglass-wky0
---

Owner reported that selecting Camera Dock on a notched MacBook displays “Camera Dock does not fit this display. Choose a larger display or reduce text size.” The screenshot also shows the current take is locked for editing. Diagnose whether the rejection comes from saved per-display line count/font size or invalid runtime display/safe-area geometry. Make the default/placement flow usable on supported notched MacBooks or provide a precise recovery path while preserving housing clearance, user typography, playback state, and the shared CameraDockLayout preview. Add deterministic geometry/native regression coverage, run Core and native tests, and build a fresh test app for owner retest. Hardware M1/M13/M14 remains owner-verified.


## Work checklist

- [x] Reproduce false rejection when auxiliary-area metadata is incomplete; the exact owner-device geometry remains unknown.
- [x] Correct the fit/recovery behavior while preserving camera-housing clearance and typography.
- [x] Add deterministic geometry regressions for incomplete, reversed, and invalid auxiliary-area metadata.
- [x] Run the 93-test Core suite, 130-test native suite, strict formatting, Bean validation, and a fresh DebugLocal build.
- [x] Prepare a fresh test app for owner retest and keep M1–M14 hardware observations pending.


- [ ] Owner confirms the new build opens Camera Dock on the notched MacBook and reports whether the housing/map alignment is correct.

Build commit: a57b4d3. iCloud Drive artifact: CueGlass/CueGlass-0.2.0-Camera-Dock-FitFix-a57b4d3.zip (SHA-256 bf34545a6a0ac22df1e98c4d4f28410b644c2d762ec95244761a240016bdc716).
