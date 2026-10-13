---
# cueglass-8ngi
title: 'ADR: lines-per-minute speed model and reverse direction'
status: completed
type: task
priority: high
created_at: 2026-10-13T19:06:06Z
updated_at: 2026-10-13T20:53:57Z
parent: cueglass-aeqt
---

PR #1 (R12, R13, R15) changes the speed contract accepted in ADR 0002: speed is chosen in lines/minute (2–240, configurable maximum), reverse direction is required, and scrubbing moves the position by gesture delta. The core timeline at `fdbffc2` accepts only 1…300 pt/s and rejects non-positive velocity.

Clarification recorded on PR #1: https://github.com/gAmUssA/CueGlass/pull/1#issuecomment-6153053777

## Accepted resolutions — ADR 0004/0005

Proposed on PR #1: https://github.com/gAmUssA/CueGlass/pull/1#issuecomment-6153087307. Accepted through ADR 0004/0005 with final lead qualifications; original ADR 0002 decision text is preserved.

- **Direction:** a separate `PlaybackDirection { forward, reverse }` flag with a positive speed, so `position(t) = anchorPosition + sign × speed × (t − anchorTime)`. Lines/min, the slider, WPM and Timed Scrolling stay unsigned, and pause stays a state. A direction change rebases at the current position. Sampling clamps to `[0, endPosition]`, where `endPosition` comes only from the actually laid-out final fragment. The session pauses at either bound. Restart returns to position 0, forward, paused.
- **Speed limits:** `PlaybackTimeline` only checks a sanity range of finite speeds between 0.1 and 2,000 pt/s. `SpeedModel` clamps lines/min to `2…configuredMax` and converts to pt/s. Timed Scrolling rejects any duration that needs a speed outside that range and says why.
- **Line advance (`preserveSource`):** line height of the presentation base font × `lineHeightMultiplier`, excluding paragraph spacing. Larger runs therefore pass the guide more slowly, which is documented as expected. The WPM estimate uses actual laid-out lines.
- **Scrub:** viewports override `scrollWheel(with:)`, and the `NSScrollView` stays non-scrollable. The gesture delta is scaled to the output's logical layout and inverted when the target viewport is vertically reflected. The first scrub pauses, then each scrub calls `seek(clamped)`. Momentum events are ignored after Play. This supersedes the "viewports are not user-scrollable" deviation.
- **Codec:** keep `formatVersion` 1, because no `.cueflow` files have shipped. Read only `preferredSpeedLinesPerMinute`, with no legacy points-per-second reader. Missing `readingStyle` fields get the handoff §3 defaults. Out-of-range values are clamped with a non-fatal diagnostic, and non-finite values reject the file. Round-trip tests cover a file with every new field missing and one with each field just past its limits.

## Checklist

- [x] Decide signed velocity vs separate direction flag; clamp at start and actual end
- [x] Move the speed limit from the fixed 1…300 pt/s range to a SpeedModel-enforced limit derived from the configured lines/minute maximum
- [x] Define the nominal line advance for preserveSource documents with mixed font sizes
- [x] Scrub translates scroll input into a timeline seek in logical space, never native NSScrollView scrolling
- [x] Write a new ADR superseding the speed and scrolling parts of ADR 0002; update 0002 status and the index
- [x] Update ScriptFileCodec for `preferredSpeedLinesPerMinute` and the new readingStyle fields with explicit defaults and clamps

## Completion summary

Delivered separate direction, bounded positive timeline speed, authoritative nominal LPM, base-font line advance, logical pause-and-seek scrub, and compatible version-1 schema defaults/diagnostics. ADR 0004 and 0005 record source-backed supersession. Unknown optional enum values default with a diagnostic per final lead qualification. Core and native regressions pass; this architecture task completion does not accept the MVP or manual gates.
