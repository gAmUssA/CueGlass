---
# cueglass-aeqt
title: CueFlow v1 MVP
status: in-progress
type: milestone
priority: high
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T19:07:34Z
---

Implement the CueFlow native macOS teleprompter MVP per `CueFlow-Codex-Handoff.md` and `CueFlow-Codex-Kickoff.md` (owner-expanded mandatory R01–R16).

Stays `in-progress` until the full implementation is accepted by independent review and test. All checklist items below are acceptance gates, not a count of implementation artifacts delivered. None is accepted by this developer metadata round.

## Committed implementation evidence (2026-10-13)

- Application/core/project/tests/docs delivered on `feat/cueflow-native` through `d278e16ae6b91f2f7684a3a2649aa756924fa578`; application integration commit `e92ffc549822521b06affa3a279ec8e727117f80`, storage hardening at `d278e16`. No application changes in the Beans integration round.
- Existing developer logs: `swift test --package-path Packages/CueFlowCore --scratch-path .build/core` → 9 Swift Testing tests passed; `scripts/test-app.sh` → 11 AppKit Swift Testing tests passed. DebugLocal and ReleaseLocal builds passed. These are developer results, not independent acceptance.
- Xcode's hosted test launcher aborted with `childPID > 0` (exit 134); direct execution of the compiled hosted bundle provided the 11-test result. This does not prove sandbox or iCloud behavior.
- Cached NSView bitmap is limited visual evidence: SwiftUI layer controls are incomplete. No complete real-window screen capture, hardware visual pass, physical smoothness or two-Mac synchronization is claimed.
- M0–M5 implementation is delivered; requirement coverage and precise remaining validation are in [implementation status](../docs/IMPLEMENTATION_STATUS.md), [README](../README.md) and [manual plan](../docs/MANUAL_TEST_PLAN.md).
- [ADR index](../docs/adr/README.md): 0001, 0002 and 0003 are accepted architecture decisions; decision acceptance is distinct from implementation acceptance.

## Milestones — independent acceptance pending

- [ ] M0a — Foundation-only core timeline with deterministic timing tests (implemented; 9 core tests in developer evidence)
- [ ] M0 — App shell, operator UI, in-memory sample in presentation viewport (implemented; independent acceptance pending)
- [ ] M1 — TXT/RTF import, diagnostics, editing, native `.cueflow` round trip, undo, autosave, local Open/Save, derived styling (implemented)
- [ ] M2 — Display-linked playback, live speed, pause/resume/restart, reading anchors, layout controls, cleanup, stall handling (implemented; hardware smoothness pending)
- [ ] M3 — Output display selection, separate output window, scaled preview, both reflection axes, calibration, disconnect handling (implemented; physical validation pending)
- [ ] M4 — iCloud configurations, container discovery, storage choice, truthful status, offline/account handling, conflicts, take isolation (implemented; owner-signed two-Mac validation pending)
- [ ] M5 — Focus-safe shortcuts, accessibility, recovery, fixtures, README / ICLOUD_SETUP / MANUAL_TEST_PLAN / IMPLEMENTATION_STATUS docs (implemented; manual accessibility and independent validation pending)

- [ ] M2.5 — Operator controls, LPM pace, commands/remapping, paragraph steps, reverse, scrubbing, timing/countdown, floating window and reading aids (R10–R16)

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
