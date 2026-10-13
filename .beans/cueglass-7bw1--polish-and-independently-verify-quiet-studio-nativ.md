---
# cueglass-7bw1
title: Polish and independently verify Quiet Studio native UI
status: in-progress
type: task
priority: high
created_at: 2026-10-13T20:40:51Z
updated_at: 2026-10-13T22:37:12Z
parent: cueglass-aeqt
---

Owner-requested native redesign. Research and proposed art: [summary](../docs/design/README.md), [concept SVG](../docs/design/quiet-studio-concept.svg). The concept is not a screenshot. Implementation follows accepted final opacity, HUD and narrow-width qualifications.

## Delivered developer evidence

- [x] Replace control wall with native toolbar, editor/stage/inspector; content uses at least 85% of window height
- [x] Verify 980/1002/1280 pt geometry, minimum editor/stage widths and inspector collapse
- [x] Curated fonts, grouped progressive disclosure, labelled states, LPM/estimated WPM and native menu/accessibility routes
- [x] Implement complete Controls HUD and floating grip with whole-window versus text-panel opacity and contrast warning
- [x] Launch actual app and inspect best-available cached light/dark renders with explicit incomplete-layer/key-window limitations
- [ ] Independent current-tip visual/accessibility review, actual key-window/menu behavior and macOS 14 runtime evidence

## Remaining acceptance

MVP remains in-progress. Full WindowServer capture permission is unavailable; no cached image is a complete screenshot or hardware visual pass. Physical/optical/fullscreen-call behavior remains in cueglass-feeg; sustained profiling in cueglass-c1kt; signed two-Mac behavior in cueglass-ykl0. Do not close this polish task from developer implementation evidence alone.

## Cumulative fix3 developer correction

Source-checked root sandbox improvements were incorporated and completed with balanced 420/578/280 panes, aspect-fit preview, compact percentage inspector, Off guide segment, native toolbar tracking and visible Present, semantic state pill, source-safe paragraph decoration, Stop Take banner and matching HUD/grip. The normal DebugLocal scheme now runs all 19 app-linked native tests via the proven unhosted debug-dylib remedy; no tests were removed. Owner specs are unchanged.

Updated Ready/Paused concept-sample native caches and direct editor/take-bar caches were inspected at 1280×800, 1002×800 and 980×640 in light/dark. Caches are supporting evidence only. Final activation attempts report key=false; composite layer/appearance omissions and asynchronous screen-layout frame restoration remain explicit limitations. Screen capture preflight false; no permission request. Independent visual/accessibility/key-window/macOS 14 acceptance remains unchecked. Signed two-Mac identifiers are explicitly deferred by owner. Developer corrections do not accept this polish task or MVP.

Independent review r2 (3569432) requires correction R2-1: fullscreen output has opaque white NSWindow backing outside clear viewport text panel, unlike dark preview. Source and actual native window properties reproduce; preserve floating/text-panel alpha semantics. Reviewer foreground gates incomplete because tester focus marker was absent; no independent visual acceptance. Evidence: /Users/vikgamov/.local/state/cueglass/r2.md.

## Cumulative fix5 developer work

- [ ] Reproduce and regress fullscreen matte parity through actual controllers
- [x] Investigate separate-process focus, menu editing and accessibility exposure
- [x] Run final native/core/build/resource gates
- [x] Push feature correction

Independent final-tip acceptance remains pending.

Fix5 evidence: actual OutputWindowController regression catches default and changed matte mismatch including clear margins; synchronizing fullscreen/preview backing resolves it on full render and aid-only updates without text relayout. Floating alpha remains 0.3, interactive backing 0.02, independent text-panel alpha 0.25. Finalized counterfactual removing only output backing assignment fails 12 assertions, other 19 native tests pass.

Focus/AX investigation is not acceptance: actual LaunchServices DebugLocal and ReleaseLocal processes remain inactive, activate=false; CGSessionCopyCurrentDictionary reports CGSSessionScreenIsLocked=1 with loginwindow active. AX trusted=true, capture=false. External AXWindows entries report AXApplication role and cannot supply a valid window subtree. No claim that missing SwiftUI text is a harness-only omission, no focus/menu/AX pass. Requires unlocked operator session and independent final-tip inspection. Evidence and commands: /Users/vikgamov/.local/state/cueglass/d6.md.

Final fix5 gates: normal DebugLocal scheme 20 native tests / 0 failures; Foundation core 14 / 0 failures; unsigned ReleaseLocal BUILD SUCCEEDED; strict swift-format, beans check and git diff --check pass. Compiled Resources include Assets.car (2234168 bytes), CueGlass.icns (64540 bytes), 1024px ReadingLine and both architectures minos14.0. No independent acceptance or source-spec/config/icon change. Focus/menu/AX obligations remain open as documented above.

Feature implementation pushed successfully: 254e460f880f4079252a5600f4b4836d6c8f9a47 on feat/cueflow-native. This metadata checkpoint records delivery only; independent acceptance remains unchecked. No PR/merge. Full report: /Users/vikgamov/.local/state/cueglass/d6.md.
