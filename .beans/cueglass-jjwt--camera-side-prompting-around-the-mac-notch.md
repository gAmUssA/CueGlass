---
# cueglass-jjwt
title: Camera-side prompting around the Mac notch
status: completed
type: feature
priority: normal
created_at: 2026-10-14T03:23:54Z
updated_at: 2026-10-17T19:57:34Z
---

User idea: offer an optional Dynamic Island-inspired presentation mode around or immediately below the Mac camera/notch so the presenter can read while maintaining eye contact with the audience. The owner has authorized an autonomous next-release prototype based on the accepted research.

- [x] Capture the user idea and eye-contact goal.
- [x] Explore a premium Quiet Studio compact prompt layout near the camera with readable text and unobstructed camera hardware.
- [x] Research native macOS window placement, notch-safe areas, supported displays, and behavior on Macs without a notch.
- [x] Define controls, accessibility, playback behavior, and multi-display fallback before implementation.

Accepted prototype defaults: opt-in Camera Dock immediately below the camera safe area; continuous scrolling through the shared PlaybackSession; top-center fallback on no-notch and external displays; distraction-free controls beneath the strip. Dynamic Island remains a visual metaphor, not an assumed macOS API.

## Research authorization (2026-10-16)

The owner authorized a bounded API and UX research pass for the next release. On 2026-10-16, after reviewing the recommendation, the owner authorized autonomous prototype work with the recommended defaults: an opt-in Camera Dock below the camera safe area, continuous scrolling, and no deployment-target increase. Keep notched-Mac hardware acceptance as a release gate.


## Research outcome (2026-10-16)

Claude/Axiom research recommends an opt-in **Camera Dock**: a compact, borderless prompt surface immediately below the built-in camera safe area, with a top-center fallback on non-notched or external displays. Keep continuous scrolling and reuse the existing playback session; defer phrase-step mode. The app can remain at macOS 14 because `NSScreen.safeAreaInsets` and the auxiliary top areas are available from macOS 12. The physical housing itself is not an app-rendered surface.

The lead independently checked Apple’s current AppKit, window collection behavior, and Info.plist documentation, plus the local macOS 27 SDK headers. One wording correction: Apple says Live Activities from a paired iPhone appear in the Mac menu bar. ActivityKit declarations in the local macOS SDK are marked unavailable to macOS apps; neither behavior provides a custom prompt rendered in the MacBook notch. The recommendation’s Camera Dock approach stands.

Before release, verify safe-area placement, full-screen behavior, keyboard routing, recording-app overlap, accessibility, and multi-display fallback on a notched MacBook. Explain that the Camera Dock remains visible in screen recordings. The accepted design report is `/Users/vikgamov/.local/state/cueglass/notch-r1/n1.md`; lead assessment is `/Users/vikgamov/.local/state/cueglass/notch-r1/lead-assessment.md`.


## Remaining feature work

- [x] Implement an opt-in Camera Dock below the camera safe area, with top-center fallback, continuous scrolling, and the macOS 14 deployment target.
- [x] Add deterministic geometry and surface-switching tests; document the placement contract and update implementation/manual-test status.
- [x] Build and run the repository gates.



## Pre-implementation test plan (2026-10-16)

- [x] Complete and review the Mode A criterion map before implementation, including deterministic geometry/surface-switching tests, adversarial input cases, and separately labeled notched-Mac hardware checks.
- [x] Implement against the accepted plan while preserving the macOS 14 minimum, shared PlaybackSession, Follow Voice and Timed Scrolling behavior, and the existing explicit microphone-consent boundary.
- [x] Run repository build/test/format/Beans gates.



## Developer correction (2026-10-16)

- [x] Make repeated Camera Dock open requests idempotent and repeated closes safe; preserve the existing panel, playback snapshot, and anchor.
- [x] Add deterministic placement, selected-display fallback, geometry-failure, preference, surface restoration, display callback/reconnect, accessibility, keyboard, adversarial source/import, timed playback, and Follow Voice/manual-takeover coverage.
- [x] Confirm the second-open regression with a counterfactual run: the old close-on-second-open branch fails `cameraDockSecondOpenReusesPanelAndRepeatedCloseIsSafe`; the restored idempotent guard passes.
- [x] Run app build, core/native tests, strict Swift formatting, Beans consistency, and diff checks.



## Independent review and test follow-up

The exact pushed tip `46ac3f65f878a57f2d4835552b57f6cd62364b03` passed local Core/native tests, macOS 14-target compilation, universal build/package verification, formatting, Beans checks, and diff checks. Independent reports found blockers and missing acceptance evidence; keep this Bean open until corrected-tip verification and direct hardware/runtime gates are complete.

- [x] Put Camera Dock Close, Play/Pause, and Adjust controls in the panel key-view loop; keep the assertion that Tab traversal reaches a control.
- [x] Preserve the Camera Dock disconnect message through the production screen-change callback; retain the take and anchor, with no automatic fallback.
- [x] Keep preferences-read, no-display, fit, and placement-recovery notices visible through the shared status-refresh path.
- [x] Add the reversed but individually valid auxiliary-area geometry case.
- [x] Complete the reported integration assertions: Preview menu/shortcut route, exact Timed Scrolling end-target preservation, Floating-equivalent Follow Voice line/session/silence-hold behavior, remaining mapped keys and numeric-field editing, accessibility tree/actions, and disabled no-document controls.
- [x] Replace wall-clock polling in the Follow Voice Camera Dock integration test with deterministic completion signaling.
- [x] Update implementation-status test counts after the new tests land.
- [x] Pass fresh independent review and testing on the corrected pushed tip. The 0.3.0 release range received full independent reviewer and tester passes (/Users/vikgamov/.local/state/cueglass/release-030/reports and final; review 5559175501 at 4f952f4), and PR #5 merged as 80d23b81f641164eeaff695169e791637cb9db93.


Review evidence: `/Users/vikgamov/.local/state/cueglass/notch-r2/correction1/verification/current/reports/reviewer.md` and `tester.md`; the full developer task ledger is `/Users/vikgamov/.local/state/cueglass/notch-r2/TASK-LEDGER.md`.


## Correction round 3 (2026-10-16)

- [x] Install the Camera Dock key-view loop after the panel and nonzero grip layout; retain it across AppKit recalculation.
- [x] Capture the Timed Scrolling target and finish before the surface switch; verify target/duration and finish within 1e-6 seconds after switching, resuming measurement, and resizing.
- [x] Update implementation-status test counts and native pass claims from the exact green run.
- [x] Run focused regressions and all repository gates, then push the corrected branch.


## Correction round 5 — failed Camera Dock open preserves state (2026-10-16)

- [x] Resolve the display target and verify a Camera Dock panel can be constructed before claiming presentation ownership or preparing an idle PlaybackSession.
- [x] On no-display and does-not-fit failures, preserve an idle session, the pre-existing presentation owner/surface, and per-display placement preferences; keep the existing persistent status copy.
- [x] Preserve any already non-idle session unchanged on either failed-first-open path; do not pause or start playback.
- [x] Add deterministic regression coverage for both failure guards, session state, owner/surface, preferences, persistent notices, and refresh behavior.
- [x] Run the required build, Core/native tests, formatting, Beans, and diff checks; commit and push this bounded correction.
- [x] Pass scoped re-check of this finding and fresh full reviewer/tester verification on the corrected tip. Covered by the 0.3.0 full independent reviews and the final7 re-check (review 5559397563 at e021d43).

## Summary of Changes

Camera Dock shipped as an opt-in surface in v0.3.0 (PR #5, merge 80d23b81f641164eeaff695169e791637cb9db93; prerelease run 39061330997). The design evolved from the researched safe-area dock into the notch-integrated island recorded in ADR 0012. The owner deferred unverified hardware and macOS 14 rows from the release gate (cueglass-1fig) and accepted three r11 observations; the M1–M14, M17 and M18 hardware rows and the macOS 14 runtime check are tracked in cueglass-feeg.
