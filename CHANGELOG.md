# Changelog

## Unreleased

- Show a four-step Welcome tour on first launch, anchored to the script, pace, Play, and Present. Replay it from Help ▸ Welcome Tour.
- Keep a running take's Follow Voice catch-up pace when the Display picker, a closed Camera Dock's placement controls, or a live Dock nudge changes only the placement.
- Describe the notch-integrated island, the prompt below the housing band, and the plain-tray opt-out in the Camera Dock first-use explainer and the README.

## 0.3.0 — 2026-10-17

- Validate Camera Dock fit using its resolved attached height, without reserving unused detached controls.
- Show Load Latest failure and retry guidance alongside the pending-script notice.
- Keep playback paused with its position retained when Camera Dock cannot restore Output.
- Synchronize the Follow Voice audio clock with captured-buffer timestamps across microphone recovery.
- Add Camera Dock, a camera-adjacent prompter with a notch-attached island, animated expansion and collapse, centered reading line, and integrated controls. Displays without a notch can use an emulated island or a plain tray.
- Add per-display placement controls and a matching operator preview while preserving the shared playback session and Reduce Motion support.
- Add a microphone picker and capture recovery across audio-device changes for Follow Voice, with quicker bounded catch-up to confirmed speech.
- Reorganize the inspector into Text, Playback, and Output tabs and refine the Quiet Studio toolbar, editor notices, preview captions, timers, and Controls panel.
- Keep macOS 14 as the minimum system version; Follow Voice requires macOS 26 or later. GitHub binaries remain unsigned and unnotarized.

## 0.2.0 — 2026-10-15

- Add opt-in macOS 26+ Follow Voice with on-device speech analysis, explicit microphone/model consent, bounded script alignment, and adaptive presenter-paced scrolling while retaining macOS 14 compatibility.
- Add prefixed Pause, Resume, Stop Following, and Stop Take voice commands using either “CueGlass” or “Prompter” as the wake phrase, with an isolated contextual command channel; keep manual controls authoritative and Timed Scrolling separate ([ADRs 0007–0011](docs/adr/README.md)).
- Improve Follow Voice model-install diagnostics, microphone startup ordering, and inspector status readability.
- Keep the release unsigned and unnotarized under the existing GitHub Actions distribution plan; signing and notarization remain deferred.

## 0.1.1 — 2026-10-14

- Harden Timed Scrolling, pace/style Undo and Redo, and presentation recovery; preserve selected displays when monitors reconnect and reject malformed documents safely.
- Show pending Timed Scrolling readiness and cancellation, preserve the editor selection during metadata refreshes, and keep fullscreen output noninteractive.
- Simplify the project README for people trying CueGlass, clarify the local-first and unsigned-release status, and move build and implementation guidance to `AGENTS.md`.

## 0.1.0 — 2026-10-13

- Keep toolbar pockets clear of the take bar and first editor/inspector rows, preserve usable 980/1002/1280 sizing and Controls key routing, and render authored black RTF legibly in Dark without changing stored source.

- Implement the native CueFlow teleprompter with source-preserving TXT/RTF import, versioned documents, rich editing, derived typography, deterministic display-linked playback, reading anchors, selected-screen output and independent reflections.
- Add real iCloud Documents configuration/discovery/download/metadata integration, honest local mode, immutable takes, future-version save protection, and native Versions/copy recovery paths.
- Add core and AppKit integration tests, synthetic fixtures, build/test commands and explicit hardware/two-Mac validation procedures.
- Record document/session/timeline and cloud ownership in ADR 0001. Commit the XcodeGen specification and real project/shared scheme as required.

- Extend the private prototype with mandatory R10–R16: floating presentation, compact Controls, LPM pace, paragraph/reverse/scrub navigation, remappable app-local commands, countdown/timed reading and static reading aids.
- Replace dense control rows with the native Quiet Studio toolbar/stage/inspector hierarchy and persist source-backed research/concept. Adopt ADR 0004/0005 without rewriting earlier accepted decisions.
- Protect every rejected native reload, make Load Latest transactional, disclose saved missing-font fallback and fix effective iCloud plist selection. Add current-contract regression/state/geometry tests; retain the explicit Xcode scheme-launcher and manual hardware/cloud gaps.

- Correct Quiet Studio preview composition, compact inspector, balanced panes, semantic state pill, source-safe paragraph decoration and locked-editing action; match the native floating grip and HUD.
- Run the full native integration suite through the normal DebugLocal scheme with an app-linked unhosted bundle, avoiding the hosted launcher assertion and duplicate Core package type identity.
- Integrate the owner-requested Reading Line artwork through native Icon Composer compilation, including compiler-generated fallback resources while retaining macOS 14 deployment metadata.
- Synchronize fullscreen and preview background mattes on initial render and color changes, preserving independent floating-window and text-panel opacity; add an actual-controller native regression.
- Preserve reading anchors and running intent through chunked measurement, install final Timed geometry atomically without rebasing its budget, and keep infeasible Restart plans cancelled with the solver reason visible.
- Settle final viewport geometry with two bounded preparation passes before atomic Timed completion; verify the actual final TextKit fragment after typography and resize on short and asynchronous scripts.
- Honor later pause, sleep, close, Restart and scrub during preparation by keeping deferred starts in the Session; reprepare on authoritative viewport handoff so both bounded passes install settled end and anchor geometry. Add native regressions across both passes, running navigation, second-document claims and original Timed budgets.
- Add a public GitHub Actions build/release pipeline for universal unsigned, unnotarized prerelease assets, with checksums and explicit release notices; defer signed distribution and iCloud validation to the next milestone.
