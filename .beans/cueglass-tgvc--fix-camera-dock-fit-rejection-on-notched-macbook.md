---
# cueglass-tgvc
title: Attach Camera Dock to the MacBook notch and repair its preview
status: in-progress
type: bug
priority: high
created_at: 2026-10-16T18:28:24Z
updated_at: 2026-10-16T19:16:43Z
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

## Owner retest and reference investigation

The owner reports the false fit error is gone. Their follow-up screenshot still shows the live Dock at the visible top of the screen with the placement caption “top of display · camera position assumed”; the small inspector map lacks a camera housing. The owner clarified that the main preview beside the editor is broken: Camera Dock selection replaces the live prompt stage with the placement map.

The `jinkun1998/another.notch` reference uses a custom `NSPanel`, transparent and non-movable, above the menu bar, anchored to the top edge and centered on the screen. It sizes the simulated notch from the auxiliary top-left/right areas and uses `safeAreaInsets.top` for physical notch height. CueGlass currently gates attached placement on `safeAreaInsets.top > 0` and configures its Camera Dock at `.floating` level below the safe edge. No target Mac display metrics are available from the development host.


## Sapphire reference and notch-integrated preview correction (2026-10-16)

The owner likes Sapphire’s integrated notch treatment. Sapphire and another.notch use app-owned, top-anchored black surfaces with display safe-area geometry; neither relies on a public Dynamic Island API. Their GPL/AGPL-licensed source informed the visual and architectural review only; CueGlass code was implemented independently.

- [x] Anchor the attached black backing at the physical display top and reserve the safe-area band above prompt text and controls.
- [x] Infer the safe-band height only from a valid, paired, top-aligned auxiliary-area set when `safeAreaInsets.top` is zero; retain the explicit fallback for incomplete/misaligned values.
- [x] Keep the editor stage as the live prompt preview; move the placement map into the Camera Dock inspector disclosure.
- [x] Run the full 96-test Core and 130-test native suites, strict formatting, `git diff --check`, and Bean validation.
- [x] Build and share the fresh DebugLocal test app.
- [ ] Owner checks notch blend, text/control clearance, and editor preview on the physical MacBook.

Fresh artifact: `CueGlass/CueGlass-0.2.0-Camera-Dock-Notch-30acc42-UNSIGNED-UNNOTARIZED.zip` in iCloud Drive; SHA-256 `476e4730df54de0ddab8923a1ea86a322fad3796f988f2f8ed98d5e2815adbf7`. The archive and copied checksum passed verification. Minimum macOS is 14.0. Physical MacBook notch/preview confirmation remains open.
