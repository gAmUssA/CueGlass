---
# cueglass-8ngi
title: 'ADR: lines-per-minute speed model and reverse direction'
status: todo
type: task
priority: high
created_at: 2026-10-13T19:06:06Z
updated_at: 2026-10-13T19:06:06Z
parent: cueglass-aeqt
---

PR #1 (R12, R13, R15) changes the speed contract accepted in ADR 0002: speed is chosen in lines/minute (2–240, configurable maximum), reverse direction is required, and scrubbing moves the position by gesture delta. The core timeline at `fdbffc2` accepts only 1…300 pt/s and rejects non-positive velocity.

Clarification recorded on PR #1: https://github.com/gAmUssA/CueGlass/pull/1#issuecomment-6153053777

## Checklist

- [ ] Decide signed velocity vs separate direction flag; clamp at start and actual end
- [ ] Move the speed limit from the fixed 1…300 pt/s range to a SpeedModel-enforced limit derived from the configured lines/minute maximum
- [ ] Define the nominal line advance for preserveSource documents with mixed font sizes
- [ ] Scrub translates scroll input into a timeline seek in logical space, never native NSScrollView scrolling
- [ ] Write a new ADR superseding the speed and scrolling parts of ADR 0002; update 0002 status and the index
- [ ] Update ScriptFileCodec for `preferredSpeedLinesPerMinute` and the new readingStyle fields with explicit defaults and clamps
