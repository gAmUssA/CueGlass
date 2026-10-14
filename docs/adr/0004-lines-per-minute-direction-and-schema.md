# Title

Lines-per-minute pace, separate direction, bounded navigation and unreleased schema

# Status

accepted

# Date

2026-10-13

# Context

Owner-expanded R12/R13/R15 and PR2 proposals require typography-independent pace, reverse, scrubbing and timing. ADR 0002 item 1's positive-only 1–300 pt/s range cannot represent the supported LPM/font range. This decision supersedes that range and positive-only motion; the pure timeline, effective-time rule, immutable snapshot, rendering and anchor contracts remain. The document format is unreleased version 1.

# Decision

Use positive finite 0.1–2000 pt/s timeline speed, separate forward/reverse direction and pure clamping to zero/actual end. Rebase on speed/direction/bound/seek changes. LPM (2–configured maximum, local maximum 10–240) is authoritative. Convert with the presentation base font's natural line height times line-height multiplier, excluding paragraph spacing in both modes. Preserve nominal LPM across relayout; explicitly label pathological layout limitations without changing saved preference. Estimated WPM uses actual laid-out line counts.

Paragraph navigation uses nonblank paragraph starts and quarter-line hysteresis; seeks preserve running state. Scrub is a seek, not native scrolling: pause on deliberate input, apply one logical scale/reflection/sign mapping and accept momentum only while latched after deliberate scrub. Play clears the latch.

Keep version 1 and read/write only preferredSpeedLinesPerMinute, default 30; ignore the legacy pt/s key. Default missing optional style fields, diagnose/default unknown style enum tokens, clamp finite ranges and reject nonfinite values. Include guide style/opacity, edge fade, margins and panel opacity, plus regular/medium/semibold/bold weight and default/serif design (missing Medium/Default). Serif design applies only to nil fontIdentifier; authored source is never restyled in storage.

# Consequences

Normal supported fonts retain reading pace, source headings retain their relative pacing in Preserve Source, and reverse stays independent of reflection. Actual-end measurement is paused/preparing work, chunked across main-run-loop turns, never whole-document work in a display callback. Existing accepted ADR 0002 text remains unchanged apart from a supersession cross-link. Owner specs and PR2 sources: [handoff](../../CueFlow-Codex-Handoff.md), [PR1 clarification](https://github.com/gAmUssA/CueGlass/pull/1#issuecomment-6153053777), [PR2 proposals](https://github.com/gAmUssA/CueGlass/pull/1#issuecomment-6153087307); tracked by `cueglass-8ngi`.
