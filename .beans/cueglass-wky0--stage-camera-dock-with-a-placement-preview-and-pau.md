---
# cueglass-wky0
title: Stage Camera Dock with a placement preview and paused Ready state
status: completed
type: feature
priority: normal
created_at: 2026-10-16T13:52:06Z
updated_at: 2026-10-17T19:57:04Z
blocked_by:
    - cueglass-c3a1
---

Complete the accepted Staged Camera Dock flow on feat/cueglass-camera-dock: placement map and honest caption, explicit commit into a visible paused Ready dock, nonmodal first-use disclosure, attached/detached styling, persistent capture disclosure, and deterministic tests. Keep macOS 14 baseline, preserve shared playback/keyboard/Follow Voice/Timed Scrolling policies, and provide a fresh unsigned local app for owner testing on a notched Mac. Physical M1–M14 checks remain owner gates.

- [x] Add a truthful placement map using the same safe-area geometry as the live Camera Dock.
- [x] Stage Camera Dock explicitly in a visible, paused Ready state with the existing anchor; Play starts it.
- [x] Replace the blocking first-use alert with a nonmodal inspector callout and retain an always-visible capture disclosure.
- [x] Apply attached notch styling and detached fallback styling without covering the housing; preserve macOS 14 and existing playback/input behavior.
- [x] Add deterministic placement-map, Ready/paused, callout, and styling regression coverage; update ADR, status, and manual test plan.
- [x] Run required Core/native/format/package checks, commit the Bean with the code, and build a fresh unsigned DebugLocal app for the owner’s notched-Mac test.

## Summary of Changes

- Added a placement map based on the same Core layout as the live Dock, including true display aspect, menu-bar band, conditional housing silhouette, dock bounds, and built-in/external fallback captions.
- Committing from Preview, Floating, or Output now pauses at the retained anchor in a visible Ready Dock; Play starts the shared session and exiting restores the prior surface and play state.
- Replaced the modal explainer with an inspector callout, kept a persistent screen-recording/full-display-share disclosure, and applied attached/detached panel styling.
- Added deterministic Core geometry/map and native surface, disclosure, and style tests; updated ADR 0012, implementation status, and the manual plan.
- Core 89 tests, native 127 tests, strict formatting, `beans check --json`, `git diff --check`, and a clean unsigned DebugLocal arm64 build for macOS 14 passed.
- Physical M1–M14 checks remain pending for owner observation.

## Final review follow-up

- [x] Fix the blocking placement-map teardown path and document the corrected M1–M14 owner gate list; tracked by child bug cueglass-17dc.
- [x] Re-run current-tip tests and build a fresh unsigned DebugLocal app for the owner’s notched-Mac checks.


## Final review follow-up result

- Fixed forced Camera Dock teardown on display loss, invalid placement, and panel close. The preview returns to its saved script size and anchor; collapsed disclosure restores the script caption/aspect, while expanded disclosure shows a current map or hides when no layout exists. Status survives refresh.
- ADR 0012 records the detached 6 pt fallback gap. All M1–M14 physical/runtime owner checks remain pending.
- This fix passes 89 Core tests, 127 native tests, strict Swift formatting, `git diff --check`, and a clean unsigned DebugLocal arm64 build targeting macOS 14.


## Final review follow-up 2 — 2c65e10

- [x] Resolve child bug @cueglass-chrp: refresh the truthful placement map after successful edits, restore ordinary floating-panel corner clipping, and update the native test count.
- [x] Run required verification on the corrected tip and build a fresh unsigned DebugLocal app for owner testing.
- [x] Keep physical M1–M14 checks pending until direct owner observation.


## Correction round 2 result — 7c50730

- Fixed stale map updates after successful width, line-count, nudge, and Reset preferences. Open-Dock nudge refreshes the map without changing paused/running playback state; ordinary FloatingRoot clipping is restored.
- Core 89 and native 130 tests pass locally. Strict Swift formatting, Beans, diff checks, and a clean unsigned DebugLocal arm64 build targeting macOS 14 pass.
- Pushed commit `7c5073083c98b03305e10c13c0beae46dff037a1` on `feat/cueglass-camera-dock`; exact-tip GitHub Actions run [38939210624](https://github.com/gAmUssA/CueGlass/actions/runs/38939210624) passed Core/native tests, formatting, universal unsigned build, and package verification.
- M1–M14 remain pending for direct owner observation. This parent remains in-progress and blocked by `cueglass-c3a1`.

## Released — 2026-10-17

The staged Camera Dock flow, its placement preview and the corrections tracked in child Beans cueglass-17dc, cueglass-chrp and cueglass-tgvc shipped in PR #5 (merge 80d23b81f641164eeaff695169e791637cb9db93) and the v0.3.0 prerelease (run 39061330997). The blocking Bean cueglass-c3a1 is completed. Physical M1–M14 checks beyond the owner's accepted r11 observations are tracked in cueglass-feeg.
