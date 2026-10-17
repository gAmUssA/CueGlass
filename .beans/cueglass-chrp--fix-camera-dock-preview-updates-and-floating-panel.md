---
# cueglass-chrp
title: Fix Camera Dock preview updates and floating-panel corners
status: completed
type: bug
priority: high
created_at: 2026-10-16T16:59:40Z
updated_at: 2026-10-16T17:30:38Z
parent: cueglass-wky0
---

Independent full review blockers on `feat/cueglass-camera-dock` at `2c65e10585399743c3d9e8723d411b9a3ac54c95` (report: `/Users/vikgamov/.local/state/cueglass/notch-r2/staged-flow/fix1-final/reports/reviewer.md`).

1. Keep the editor placement map truthful after a successful Camera Dock preference edit. With the Dock closed and map expanded, width, line count, nudge, and Reset must update the displayed layout. When collapsed, the map stays hidden and script caption/aspect stay intact. With the Dock open, nudge updates the map to the live Dock frame without changing the current play/pause state. Preserve the invalid-placement path and avoid routing nudge through the resize/pause path.
2. Restore the ordinary floating panel root's 14 pt corner radius and `masksToBounds` clipping; keep Camera Dock attached bottom-only corners and detached all-corner styling unchanged.
3. Update `docs/IMPLEMENTATION_STATUS.md` from 126 to 127 native tests based on exact-tip CI run 38933730280, without changing any M1–M14 owner-test status.

Add deterministic regressions for preference-driven placement-map updates and non-Dock floating clipping. Run Core/native tests, strict formatting, Beans, diff checks, and an unsigned DebugLocal build, then commit and push the bounded correction. Do not sign, notarize, release, open a PR, or mark physical M1–M14 checks passed.

## Checklist

- [x] Keep the expanded preview map in sync with successful Camera Dock preference changes and prove open-Dock nudge does not change playback state.
- [x] Restore 14 pt clipping on ordinary floating panels and add a regression without changing Camera Dock styling.
- [x] Update the implementation status to cite 127 native tests on CI, record the 130-test local regression suite, and leave M1–M14 pending.
- [x] Run required tests and checks; commit and push the bounded correction.

## Summary of Changes

- Successful Camera Dock preference edits now refresh the expanded map; the collapsed map stays hidden and preserves the script caption, aspect ratio, and logical size.
- Open-Dock nudges render the changed placement directly when viewport size is unchanged, preserving paused or running playback state. Viewport-size changes keep the existing resize path.
- Ordinary FloatingRoot restores its 14 pt corner radius and clipping; Camera Dock attached and detached corner styles remain unchanged.
- Added deterministic tests: `cameraDockPlacementPreviewTracksSuccessfulPreferenceEdits`, `openCameraDockNudgeRefreshesMapWithoutChangingPlaybackState`, and `ordinaryFloatingRootRetainsRoundedClipping`.
- Core: 89 passed. Full native suite: 130 passed, including the three regressions. Strict formatting, `beans check --json`, and `git diff --check` passed. A clean unsigned DebugLocal arm64 app build targets macOS 14.
- Exact-tip GitHub Actions run [38939210624](https://github.com/gAmUssA/CueGlass/actions/runs/38939210624) passed commit `7c5073083c98b03305e10c13c0beae46dff037a1`, including Core/native tests, formatting, universal unsigned build, and package verification.
- `docs/IMPLEMENTATION_STATUS.md` records 127 native tests from prior exact-tip run 38933730280 and the current 130-test local regression suite. M1–M14 remain pending.
- Pushed to `feat/cueglass-camera-dock`; no PR was opened. The local unsigned build was not handed off as a final owner binary before independent verification.
