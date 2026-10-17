---
# cueglass-tgvc
title: Attach Camera Dock to the MacBook notch and repair its preview
status: in-progress
type: bug
priority: high
created_at: 2026-10-16T18:28:24Z
updated_at: 2026-10-17T01:18:52Z
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

## Sapphire-style notch motion follow-up (2026-10-16)

The owner likes Sapphire’s integrated notch treatment. Their latest screenshot still shows a gap below the notch, a square panel, and no expansion animation. The supplied Sapphire demo is the visual target. Preserve the shared playback session and macOS 14 support; do not sign, notarize, merge, or release this correction.

- [x] Diagnose and correct target-screen detection/geometry so Camera Dock visibly joins the physical notch with no gap, including a clear user-controlled fallback when macOS omits notch geometry.
- [x] Animate a compact notch-connected surface into the expanded prompt, with smooth rounded edges and a matching retract transition; honor Reduce Motion.
- [x] Preserve readable prompt text, controls, shared playback state, full-screen behavior, and no-notch/external fallbacks.
- [x] Add deterministic geometry/transition coverage and rerun Core/native suites, formatting, and Beans checks.
- [x] Build and share a fresh macOS 14-targeted DebugLocal artifact for owner retest.
- [ ] Owner confirms notch bleed, rounded expanded shape, motion, and prompt readability on the physical MacBook.

Fresh local test artifact: `CueGlass/CueGlass-0.2.0-Sapphire-Notch-Morph-r2-20261016-UNSIGNED-UNNOTARIZED.zip` in iCloud Drive. SHA-256: `80ad0c200503bf445719fb58f069f3edfffb98cbf319e4ecc06a981ba814325f`. Core 99 and native 131 tests pass; minimum macOS 14.0. Owner hardware confirmation remains open.


## Owner retest: shape, motion, and text clipping (2026-10-17)

The owner tested the r2 build and reports it still has no finesse or satisfying animation. The screenshot shows an oversized, nearly full-width tray and prompt text visibly clipped along the top edge; the motion is not perceptible in use. Treat r2 as superseded. Tighten the resting and expanded silhouette, make expansion/retraction feel intentional and connected to the notch, and correct prompt viewport alignment without changing the operator's chosen font size. Keep macOS 14 support and existing playback behavior.

- [x] Diagnose why the live prompt's top line is clipped in the owner's screenshot and fix its safe-area/layout alignment.
- [x] Refine attached dock proportions, shoulders, and corner radii for a compact premium silhouette.
- [x] Replace the barely perceptible transition with a clear, polished expansion/retraction animation that respects Reduce Motion.
- [x] Add deterministic regression coverage for expanded content bounds and transition endpoints/timing.
- [x] Run relevant Core/native tests and build a fresh unsigned test artifact for owner retest.
- [ ] Owner confirms the tray shape, motion, and prompt readability on the notched MacBook.

## Claude + Axiom developer handoff (2026-10-17)

The owner requested: “could you pass development to claude + axiom”. Continue Bean `cueglass-tgvc` from recorded base `adfaab04335d32093263263e2021d3e24ec2ebc2` in the isolated worktree `/Users/vikgamov/.worktrees/cueglass-notch-polish-r3` on `fix/cueglass-notch-polish-r3`. Assigned Herdr seat: `cue-designer` (Claude, live pane `w5:p7`), developer responsibility. The report requires Axiom macOS, design, and Apple-docs skills.

The brief is `/Users/vikgamov/.local/state/cueglass/notch-r3/reports/brief-developer.md`; accepted research is `/Users/vikgamov/.local/state/cueglass/notch-preview-competitor-research/reports/architect.md`; owner screenshot is `/Users/vikgamov/.local/state/cueglass/notch-r3/evidence/owner-r3-notch.png`; reference video is `https://raw.githubusercontent.com/cshariq/Sapphire/main/Assets/sapphire-demo.mp4`. The authorized patch copied to the worktree is `/Users/vikgamov/.local/state/cueglass/notch-r3/authorized-diff.patch`, SHA-256 `b32ec4f42106105d0548d8f36eec2ee79711558fdf3f818ae22b3b264d222afa`.

The original dirty worktree `/Users/vikgamov/.worktrees/cueglass-camera-dock` remains untouched. The Claude branch starts at the recorded base and contains only the allowed patch. No build result is accepted yet. Required next gates are developer report, independent review and testing, then the owner’s physical notched-Mac visual retest. No merge, signing, notarization, or release is authorized here.

## Claude + Axiom developer round r3 (2026-10-17)

Diagnosis: the presentation viewport reserves one fifth of its height above the reading guide (the operator passes a fixed 0.2 for the Dock). In a three-line strip that band held most of the previous line and the camera-safe edge hard-clipped it; the controls band stayed in the black tray while playing, so the tray read as oversized. CueFlowCore now sizes the logical viewport so the band equals the guide offset minus an 8 pt margin (`hiddenViewportTop`), and the Dock clips it inside a content container; the guide line is the first visible line and exactly the chosen line count fits below it. The attached silhouette is one Core Animation path (housing stem, up to 12 pt shoulder fillets, 22 pt tray corners, 14 pt parked chin) driven by a bounded spring with delayed content fade; Reduce Motion keeps a 0.15 s crossfade only. Showing the Dock unfurls it; Adjust ▸ Collapse to Notch pauses and parks it; hover peeks; Play opens it and drops the controls band from the tray.

Not changed: `CueFlow/Editor/OperatorWindowController.swift` is outside this task's allowed paths, so the editor preview still uses the style's guide fraction and a literal `0.2` remains there; a two-line follow-up is proposed in the round report. The `forceNotchAttachment` preference has no inspector control yet. The development host has no notch; M15/M16 remain owner observations.

r3 verification (macOS 27.0.1 host, Xcode 27): Core 104 tests pass; native DebugLocal suite 131 tests pass; branch CI run 38992977384 (`ed6d669`) is green after the first run on a 1024 pt runner display exposed a fractional panel width and a reflow-sensitive timed test, both fixed; strict swift-format, `git diff --check` pass. `beans check --json` reports a pre-existing broken `blocked_by` link from `cueglass-wky0` to `cueglass-c3a1` (that Bean is untracked in the shared checkout and absent from this branch; outside this task's allowed paths). Fresh unsigned, unnotarized, ad-hoc-signed DebugLocal app: `CueGlass-0.2.0-Notch-Polish-r3-UNSIGNED-UNNOTARIZED.zip` in the r3 reports directory, minimum macOS 14.0; SHA-256 `785d36a0a3ee6b5b72646787c5c89ab3eb7adea41e667208f23aaa394f55fcfe`, also recorded beside it. Owner hardware confirmation (M15/M16) remains open.
