---
# cueglass-trhd
title: Reorganize the inspector into Text, Playback, and Output tabs
status: completed
type: task
priority: normal
created_at: 2026-10-17T03:55:34Z
updated_at: 2026-10-17T19:57:35Z
---

Owner asked for a critical UX pass: the inspector was one long scroll grouped by implementation (Text, Reading Guide, Output, then collapsed Layout, Colors, Timing, Controls & Keys, Follow Voice far down) with paragraphs of inline prose. Rebuild it as three task tabs on a native grouped form: Text (font, layout, colors, reading guide), Playback (pace, countdown, Timed Scrolling, Follow Voice with language and microphone, controls and shortcuts), Output (presentation surface and display, Camera Dock placement, floating window). Prose moves to tooltips and one-line footers. Toolbar, transport, and floating Controls panel unchanged.

## Work checklist

- [x] Audit the operator window against Axiom HIG and macOS inspector guidance; toolbar and Controls panel kept.
- [x] Rebuild the inspector as Text / Playback / Output tabs on a grouped form with footers and tooltips.
- [x] Keep every binding, action, and accessibility label; native suite green.
- [x] Owner reviewed the layout; leftovers fixed: bordered Size and Finish-in fields, a named placeholder for an unattached display, the "On This Mac" subtitle, a usable pace slider in the Controls panel, and transport skip symbols for the paragraph steps.
The owner's r11 observations (2026-10-17) did not name the Controls panel or toolbar; that retest moved to cueglass-feeg.

## Summary of Changes

The inspector shipped as Text, Playback and Output tabs on a grouped form with footers and tooltips, with the owner's r9 leftovers fixed, in v0.3.0 (PR #5, merge 80d23b81f641164eeaff695169e791637cb9db93). The Controls panel and toolbar hardware retest is tracked in cueglass-feeg.
