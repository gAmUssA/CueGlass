---
# cueglass-w4c7
title: Keep catch-up pace across placement-only Camera Dock edits and align the Dock explainer with ADR 0012
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T19:46:38Z
updated_at: 2026-10-17T19:59:43Z
parent: cueglass-aeqt
---

GitHub issues #6 and #7, carried from the 0.3.0 release reviews on PR #5 (Copilot review 5559388091; independent advisory on review 5559397563; advisory A1 on reviews 5559175501 and 5559397563).

#6: three placement-only Camera Dock paths still run a full render() during a running take: the Display picker with the preview expanded (OperatorWindowController.selectDisplay), closed-Dock width/lines/nudge/island edits with the preview expanded (setCameraDockPreference), and a live Dock nudge whose viewport size is unchanged (FloatingPrompterWindowController.updateCameraDockPlacement). Each re-measures and session.updateLayout resets a Follow Voice catch-up velocity to the nominal pace. Placement-only updates must refresh only the placement map or reposition the live Dock window; render() runs only when the playback layout changes (a viewport size change keeps cameraDockResized). PlaybackSession.updateLayout is unchanged, an open Dock does not move on picker changes (ADR 0012), and the preference-reload behavior from cueglass-j71o stays.

#7: the first-use explainer and the README still describe the pre-island placement. Both must say the black backing is anchored to the display top around the housing (notch or emulated island), the prompt stays below the housing band, and the island can be turned off for a plain tray, while keeping the capture disclosure.

- [x] Regressions in the running-take pattern of placementPreviewToggleLeavesRunningTakeVelocityAndLayoutUntouched for (a) a Display-picker change with the preview expanded, (b) closed-Dock width, lines, nudge and island edits with the preview expanded, (c) a live Dock nudge with an unchanged viewport size; each leaves velocity, position continuity, session.measuring and renderGeneration unchanged while the map or Dock placement still updates; shown failing on the unfixed source and passing after.
- [x] Route the three placement-only paths through the shared placement-map refresh; keep render() for viewport size changes and placement failures.
- [ ] Reword OperatorWindowController.cameraDockExplainer and the README Camera Dock line per ADR 0012; update the explainer regression.
- [x] Run the Core and native suites, strict swift-format, beans check, git diff --check and the universal unsigned ReleaseLocal build (Core 114, native 172, format clean, beans check success, diff check clean, universal 0.3.0/build 3 ReleaseLocal build succeeded on 2026-10-17).
- [ ] Push fix/cueglass-030-followups and record its CI runs.
