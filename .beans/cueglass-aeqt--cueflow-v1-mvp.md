---
# cueglass-aeqt
title: CueFlow v1 MVP
status: in-progress
type: milestone
priority: high
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T20:53:57Z
---

Implement the CueFlow native macOS teleprompter MVP per `CueFlow-Codex-Handoff.md` and `CueFlow-Codex-Kickoff.md` (owner-expanded mandatory R01–R16).

Stays `in-progress` until the full implementation is accepted by independent review and test. All checklist items below are acceptance gates, not a count of implementation artifacts delivered. None is accepted by this developer metadata round.

## Developer implementation evidence (2026-10-13)

- Cumulative R01–R16 implementation delivered on `feat/cueflow-native`; current-tip independent acceptance is pending. Owner specifications were merged unchanged; only the two assigned metadata commits were cherry-picked.
- Core: 14 Swift Testing tests. Native direct hosted-bundle runner: 18 tests in two suites. Supplemental tester probe: 39 assertions, zero failures, with the old pt/s oracle adapted to retained position under required LPM semantics.
- DebugLocal/ReleaseLocal and unsigned DebugICloud/ReleaseICloud builds pass. Synthetic processed cloud plists validate configuration precedence, not signed owner synchronization.
- Xcode scheme launcher still aborts `childPID > 0`, exit 134; direct runner is separate evidence.
- Actual launched geometry verified at 980/1002/1280 pt. Cached view renders have incomplete layer/key-window limitations and are not complete screenshots or independent visual acceptance.
- Accepted superseding ADR 0004/0005 and source-backed design research/concept are committed. See [implementation status](../docs/IMPLEMENTATION_STATUS.md), [design](../docs/design/README.md) and [manual plan](../docs/MANUAL_TEST_PLAN.md).
- `cueglass-o9d1` tracks developer delivery; `cueglass-7bw1` remains in-progress for independent visual/accessibility acceptance. Owner cloud, physical/optical and sustained performance gates remain open.

## Milestones — independent acceptance pending

- [ ] M0a — Foundation-only core timeline with deterministic timing tests (implemented; 14 core tests in developer evidence)
- [ ] M0 — App shell, operator UI, in-memory sample in presentation viewport (implemented; independent acceptance pending)
- [ ] M1 — TXT/RTF import, diagnostics, editing, native `.cueflow` round trip, undo, autosave, local Open/Save, derived styling (implemented)
- [ ] M2 — Display-linked playback, live speed, pause/resume/restart, reading anchors, layout controls, cleanup, stall handling (implemented; hardware smoothness pending)
- [ ] M3 — Output display selection, separate output window, scaled preview, both reflection axes, calibration, disconnect handling (implemented; physical validation pending)
- [ ] M4 — iCloud configurations, container discovery, storage choice, truthful status, offline/account handling, conflicts, take isolation (implemented; owner-signed two-Mac validation pending)
- [ ] M5 — Focus-safe shortcuts, accessibility, recovery, fixtures, README / ICLOUD_SETUP / MANUAL_TEST_PLAN / IMPLEMENTATION_STATUS docs (implemented; manual accessibility and independent validation pending)

- [ ] M2.5 — Implemented operator controls, LPM pace, commands/remapping, paragraph steps, reverse, scrubbing, timing/countdown, floating window and reading aids (R10–R16)

## Requirements — each needs independent evidence or an accepted named blocker

- [ ] R01 Native macOS application
- [ ] R02 Import text files (UTF-8/UTF-16, Unicode, paragraph breaks)
- [ ] R03 Import RTF documents (explicit `.rtf` document type, unsupported-content diagnostics)
- [ ] R04 Synchronize between Macs using iCloud — needs owner setup and two-Mac evidence (cueglass-ykl0)
- [ ] R05 Customize fonts and text size without destroying source formatting
- [ ] R06 Faster/slower scrolling with explicit play/pause
- [ ] R07 Smooth scrolling — needs hardware and profiling evidence (cueglass-feeg, cueglass-c1kt)
- [ ] R08 Independent horizontal/vertical reflection — needs optical check (cueglass-feeg)
- [ ] R09 Present on another screen — needs physical display check (cueglass-feeg)

- [ ] R10 Floating always-on-top prompter window
- [ ] R11 Compact controls with the operator window hidden
- [ ] R12 Font-independent LPM pace and estimated WPM
- [ ] R13 Restart, paragraph step, reverse, pause-and-scrub
- [ ] R14 App-local remappable clicker/pedal keys, editor-safe
- [ ] R15 Elapsed/remaining, countdown, Timed Scrolling and end hold
- [ ] R16 Guide style, edge fade, side margins, panel opacity, hide controls

## Related work and follow-ups

- cueglass-xfha — ADR 0001 artifact/index delivery; completing it does not accept the MVP
- cueglass-ykl0 — Owner iCloud setup and two-Mac verification (R04), remains todo
- cueglass-feeg — Physical display and visual verification (R07, R08, R09), remains todo
- cueglass-c1kt — Performance profiling on hardware (R07), remains todo

- cueglass-8ngi — ADR for LPM/reverse/timing, superseding ADR 0002 speed contract
