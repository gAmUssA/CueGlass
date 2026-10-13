# 0002 — Deterministic playback timeline, immutable take snapshot, TextKit 2 display-linked rendering

- **Status:** accepted
- **Date:** 2026-10-13
- **Related:** [0001](README.md) (pending), [0003](0003-icloud-document-storage.md), `CueFlow-Codex-Handoff.md` §4 and §6, requirements R05–R07

## Context

Playback must be smooth and time-based across refresh rates (R07), speed must change live (R06), and typography changes must keep the reading position (R05). Cloud reloads and editor changes must never replace the text of a running take. Two viewports (operator preview and external output) must not advance a shared offset twice. Timing logic needs deterministic tests without AppKit.

Options considered: frame-count or fixed-step timers (rejected: depend on refresh rate); sharing the document's text storage with the viewport (rejected: an edit or revert mutates the take mid-frame); copy-on-write diffing (rejected: no requirement needs it); Metal rendering (rejected until NSTextView-based strategies fail on hardware); `CADisplayLink(target:selector:)` (unavailable on macOS).

## Decision

1. **Foundation-only timeline.** `PlaybackTimeline` in `Packages/CueFlowCore` is a value type: `position(t) = anchorPosition + velocity × (t − anchorTime)`. Sampling is side-effect free. `play`, `pause`, `setVelocity` and `seek` rebase explicitly and reject non-finite values, times before the anchor, and velocities outside 1…300 pt/s. Pause is a state, not zero velocity. Time is host-media-time seconds from an injectable `PlaybackClock` (`CACurrentMediaTime()` in the app, `ManualClock` in tests); never `Date`.
2. **Effective-time and stall rules.** Commands use `max(now, lastPresentedTarget)` so a speed decrease never steps text backward. A gap above `StallPolicy.threshold` (0.5 s) pauses at the last presented position instead of leaping.
3. **Immutable take snapshot.** A take holds a `ScriptSnapshot` (snapshot ID, document ID, source revision, immutable `NSAttributedString` copy). The editor is read-only while a take exists. A document revision change sets a pending-revision notice; loading it is allowed only while paused. The UTF-16 anchor carries over only when the plain text is identical; otherwise the position resets to 0.
4. **TextKit 2 renderer.** The presentation viewport is a non-editable `NSTextView(usingTextLayoutManager: true)` in a non-scrollable `NSScrollView`. No code touches `layoutManager`; DEBUG builds assert on `willSwitchToNSLayoutManagerNotification`. Layout is ensured in a bounded lookahead region; the end position comes only from an actually laid-out final fragment, never from estimated usage bounds.
5. **Display link.** Each viewport owns a `DisplayLinkDriver` that creates `NSView.displayLink(target:selector:)` on `.main` in `.common` mode, targeting a `WeakLinkProxy` so no retain cycle exists. Each callback samples `position(at: targetTimestamp)`. Only the authoritative viewport (output when active, otherwise preview) reports presented frames. The link is paused when not running and invalidated on stop or window removal.
6. **Reading anchors.** A snapshot-scoped UTF-16 offset, aligned down to a grapheme boundary, plus an intra-line fraction; relayout pauses, captures, rebuilds presentation attributes, restores and stays paused.

## Consequences

- Easier: timing behavior is unit-tested deterministically; refresh rate cannot change speed; cloud changes cannot alter a running take.
- Harder: editing during a take is not supported in v1; the operator must pause to load a newer revision; fuzzy anchor mapping across edits is not provided.
- Later work must honor: no per-frame RTF parsing, document rebuilds, saves or SwiftUI broadcasts; no `layoutManager` access; no `Date` in playback.

### Implementation status (2026-10-13)

- **Implemented and tested:** items 1–2 and the core-pure anchor, grapheme and carry-over helpers in `Packages/CueFlowCore` at `fdbffc2` (7 Swift Testing tests passing).
- **Implemented, not accepted:** items 3–6 exist in the primary developer's uncommitted native work, with anchors inside `PrompterViewport` rather than a separate resolver type.
- **Recommended, not implemented:** a typed `PlaybackInstant` and the narrower `TimelineError` taxonomy from the architect note (core uses plain `Double` and `invalidTime` / `invalidPosition` / `invalidVelocity`); a `ScrollStrategy` switch (current code has a boolean fractional-translation flag); a ≤ 4 Hz progress-label timer. The scrolling strategy and smoothness are unverified on hardware — bean `cueglass-feeg`; profiling — bean `cueglass-c1kt`.
