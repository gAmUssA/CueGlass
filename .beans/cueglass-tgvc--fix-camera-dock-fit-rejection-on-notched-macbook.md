---
# cueglass-tgvc
title: Fix Camera Dock fit rejection on notched MacBook
status: in-progress
type: bug
priority: high
created_at: 2026-10-16T18:28:24Z
updated_at: 2026-10-16T18:37:03Z
parent: cueglass-wky0
---

Owner reported that selecting Camera Dock on a notched MacBook displays “Camera Dock does not fit this display. Choose a larger display or reduce text size.” The screenshot also shows the current take is locked for editing. Diagnose whether the rejection comes from saved per-display line count/font size or invalid runtime display/safe-area geometry. Make the default/placement flow usable on supported notched MacBooks or provide a precise recovery path while preserving housing clearance, user typography, playback state, and the shared CameraDockLayout preview. Add deterministic geometry/native regression coverage, run Core and native tests, and build a fresh test app for owner retest. Hardware M1/M13/M14 remains owner-verified.


## Work checklist

- [x] Reproduce false rejection when auxiliary-area metadata is incomplete; the exact owner-device geometry remains unknown.
- [x] Correct the fit/recovery behavior while preserving camera-housing clearance and typography.
- [x] Add deterministic geometry regressions for incomplete, reversed, and invalid auxiliary-area metadata.
- [x] Run the 93-test Core suite, 130-test native suite, strict formatting, Bean validation, and a fresh DebugLocal build.
- [ ] Prepare a fresh test app for owner retest and record remaining physical checks.
