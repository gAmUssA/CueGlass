---
# cueglass-tzn2
title: Add brief first-run tour
status: in-progress
type: feature
created_at: 2026-10-28T16:53:39Z
updated_at: 2026-10-28T16:53:39Z
---

A brief 'run the app for the first time' tour shown on first launch.
- [x] Design note (steps, entry/exit, replay from menu)
- [x] Implement
- [x] Tests and manual-plan entry

Four non-modal coachmarks anchor to the script, pace, Play, and Present. The tour auto-starts once and replays from Help ▸ Welcome Tour. Manual T1–T7 were run through Accessibility scripting on 2026-10-29: T1, T2, T3, T5, T7 pass, T4 is partial (no VoiceOver speech or Tab sent), and T6 is not run (needs two displays and a full-screen Space). The popover re-anchors after toolbar layout changes. The bean stays in progress until T4 and T6 are observed.
