---
# cueglass-7bw1
title: Polish and independently verify Quiet Studio native UI
status: in-progress
type: task
priority: high
created_at: 2026-10-13T20:40:51Z
updated_at: 2026-10-13T20:40:51Z
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
