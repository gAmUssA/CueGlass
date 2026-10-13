---
# cueglass-aeqt
title: CueFlow v1 MVP
status: in-progress
type: milestone
priority: high
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T18:53:57Z
---

Implement the CueFlow native macOS teleprompter MVP per `CueFlow-Codex-Handoff.md` and `CueFlow-Codex-Kickoff.md`.

Stays `in-progress` until the full implementation is accepted by independent review and test. Checked items below carry committed evidence; unchecked items are not accepted yet.

## Status as of 2026-10-13

- Core package `Packages/CueFlowCore` committed at `fdbffc2` on `feat/cueflow-native`; `swift test --package-path Packages/CueFlowCore` → 7 tests passed.
- Native app (Xcode project, AppKit/SwiftUI shell, document, viewport, display link, output window, iCloud plumbing) exists as uncommitted work on the primary developer's branch. An initial build and seven direct integration tests were observed passing. Implementation and review are **not accepted**.
- Architecture decisions: `docs/adr/` (0001 pending from the primary developer; 0002, 0003 accepted).

## Milestones

- [x] M0a — Foundation-only core timeline with deterministic ManualClock tests (`fdbffc2`, 7 tests passing)
- [ ] M0 — App shell, operator UI, in-memory sample in presentation viewport (built; not accepted)
- [ ] M1 — TXT/RTF import, diagnostics, editing, native `.cueflow` round trip, undo, autosave, local Open/Save, derived styling
- [ ] M2 — Display-linked playback, live speed, pause/resume/restart, reading anchors, layout controls, cleanup, stall handling
- [ ] M3 — Output display selection, separate output window, scaled preview, both reflection axes, calibration, disconnect handling
- [ ] M4 — iCloud configurations, container discovery, storage choice, truthful status, offline/account handling, conflicts, take isolation
- [ ] M5 — Focus-safe shortcuts, accessibility, recovery, fixtures, README / ICLOUD_SETUP / MANUAL_TEST_PLAN / IMPLEMENTATION_STATUS docs

## Requirements (each needs implementation plus evidence or a named blocker)

- [ ] R01 Native macOS application
- [ ] R02 Import text files (UTF-8/UTF-16, Unicode, paragraph breaks)
- [ ] R03 Import RTF documents (explicit `.rtf` document type, unsupported-content diagnostics)
- [ ] R04 Synchronize between Macs using iCloud — needs owner setup and two-Mac evidence (follow-up bean)
- [ ] R05 Customize fonts and text size without destroying source formatting
- [ ] R06 Faster/slower scrolling with explicit play/pause
- [ ] R07 Smooth scrolling — needs hardware evidence (follow-up bean)
- [ ] R08 Independent horizontal/vertical reflection — needs optical check (follow-up bean)
- [ ] R09 Present on another screen — needs physical display check (follow-up bean)

## Follow-up beans

- cueglass-xfha — Record ADR 0001 native app architecture (primary developer)
- cueglass-ykl0 — Owner iCloud setup and two-Mac verification (R04)
- cueglass-feeg — Physical display and visual verification (R07, R08, R09)
- cueglass-c1kt — Performance profiling on hardware (R07)
