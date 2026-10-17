---
# cueglass-ta8r
title: Keep a running take's velocity when the Output inspector tab toggles the placement preview
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T18:18:51Z
updated_at: 2026-10-17T18:19:12Z
parent: cueglass-aeqt
---

Copilot review 5559273824 on PR #5 (previously missed, introduced by 8896f51): OperatorControls calls setCameraDockPlacementPreviewExpanded(true/false) from the Output inspector tab's onAppear/onDisappear, and that setter ran a full render(). During an active take, render() re-measures and the measurement callback calls session.updateLayout, which resets the timeline velocity to the nominal pace. Switching inspector tabs during a Follow Voice catch-up therefore dropped the boosted velocity and flipped session.measuring on a running take. The expanded flag drives only the preview placement map, so the setter must update that map without re-rendering or re-measuring the playback surfaces. PlaybackSession.updateLayout and the other render() callers are unchanged.

- [x] Add a regression: a running take with a catch-up velocity above nominal keeps its velocity, position continuity, session.measuring and renderGeneration across expand and collapse, while the flag and preview map still update. Shown failing on the prior source and passing after.
- [x] Update only the preview placement map from setCameraDockPlacementPreviewExpanded; share that map refresh with render().
- [x] Run the Core and native suites, strict formatting, Beans integrity, diff check and the universal unsigned ReleaseLocal build with checksum.
- [ ] Commit and push fix/cueglass-030-final7, then fast-forward release/cueglass-030 and record the exact-head CI runs.

## Correction — 2026-10-17

`setCameraDockPlacementPreviewExpanded` now sets the flag and refreshes only `preview.placementMapView.map` through the shared `updatePlacementMapPreview()`, which `render()` also uses for the same map assignment. No render, no re-measure, no `session.updateLayout`, so a running take keeps its velocity, position and `renderGeneration` across inspector tab switches. `PlaybackSession.updateLayout` and the other `render()` callers (`selectDisplay`, `setCameraDockPreference`) are unchanged. The regression `placementPreviewToggleLeavesRunningTakeVelocityAndLayoutUntouched` fails on the prior source (render generation advanced, catch-up velocity reset to nominal, position continuity broken) and passes after the change; the full native suite (169 tests) and Core suite (114 tests) pass.
