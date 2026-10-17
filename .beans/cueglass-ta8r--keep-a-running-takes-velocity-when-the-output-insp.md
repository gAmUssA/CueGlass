---
# cueglass-ta8r
title: Keep a running take's velocity when the Output inspector tab toggles the placement preview
status: completed
type: bug
priority: high
created_at: 2026-10-17T18:18:51Z
updated_at: 2026-10-17T19:55:09Z
parent: cueglass-aeqt
---

Copilot review 5559273824 on PR #5 (previously missed, introduced by 8896f51): OperatorControls calls setCameraDockPlacementPreviewExpanded(true/false) from the Output inspector tab's onAppear/onDisappear, and that setter ran a full render(). During an active take, render() re-measures and the measurement callback calls session.updateLayout, which resets the timeline velocity to the nominal pace. Switching inspector tabs during a Follow Voice catch-up therefore dropped the boosted velocity and flipped session.measuring on a running take. The expanded flag drives only the preview placement map, so the setter must update that map without re-rendering or re-measuring the playback surfaces. PlaybackSession.updateLayout and the other render() callers are unchanged.

- [x] Add a regression: a running take with a catch-up velocity above nominal keeps its velocity, position continuity, session.measuring and renderGeneration across expand and collapse, while the flag and preview map still update. Shown failing on the prior source and passing after.
- [x] Update only the preview placement map from setCameraDockPlacementPreviewExpanded; share that map refresh with render().
- [x] Run the Core and native suites, strict formatting, Beans integrity, diff check and the universal unsigned ReleaseLocal build with checksum.
- [x] Commit and push fix/cueglass-030-final7, then fast-forward release/cueglass-030 and record the exact-head CI runs. Commit e021d4352b114e2a8c14499423917ea5a5c60b33; runs 39057577837 (push, fix/cueglass-030-final7), 39057578866 (push, release/cueglass-030) and 39057584583 (pull_request, PR #5), all success.

## Correction — 2026-10-17

`setCameraDockPlacementPreviewExpanded` now sets the flag and refreshes only `preview.placementMapView.map` through the shared `updatePlacementMapPreview()`, which `render()` also uses for the same map assignment. No render, no re-measure, no `session.updateLayout`, so a running take keeps its velocity, position and `renderGeneration` across inspector tab switches. `PlaybackSession.updateLayout` and the other `render()` callers (`selectDisplay`, `setCameraDockPreference`) are unchanged. The regression `placementPreviewToggleLeavesRunningTakeVelocityAndLayoutUntouched` fails on the prior source (render generation advanced, catch-up velocity reset to nominal, position continuity broken) and passes after the change; the full native suite (169 tests) and Core suite (114 tests) pass.

## Summary of Changes

Fixed in e021d4352b114e2a8c14499423917ea5a5c60b33: the inspector tab toggle refreshes only the placement map through `updatePlacementMapPreview()`, with the regression `placementPreviewToggleLeavesRunningTakeVelocityAndLayoutUntouched` shown failing on the prior source and passing after. Independent scoped re-check PASS (review 5559397563, bound to e021d43). Shipped in PR #5 (merge 80d23b81f641164eeaff695169e791637cb9db93) and released as v0.3.0 (prerelease run 39061330997). The sibling placement-only paths named as the advisory follow-up are GitHub issue #6, tracked in cueglass-w4c7.
