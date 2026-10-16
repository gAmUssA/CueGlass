---
# cueglass-chrp
title: Fix Camera Dock preview updates and floating-panel corners
status: in-progress
type: bug
priority: high
created_at: 2026-10-16T16:59:40Z
updated_at: 2026-10-16T17:22:16Z
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
- [ ] Run required tests and checks; commit and push the bounded correction.
