# CueFlow — kickoff prompt

Read `CueFlow-Codex-Handoff.md` and implement the native macOS application it specifies. Treat that document as the implementation brief, not as evidence that any code already exists.

Inspect the repository, its instructions, existing changes, and available toolchain first. Preserve unrelated work. Follow any repository AGENTS.md. Integrate with an existing project where appropriate; otherwise create a real Xcode project with a shared scheme and a Foundation-only Swift core package for deterministic playback tests.

Use CueFlow as a provisional name. Default to macOS 14+, SwiftUI controls, AppKit document/window ownership and text rendering, an NSDocument-owned native `.cueflow` format, a display-linked time-based playback engine, and iCloud Drive document synchronization. Verify exact platform APIs against the installed SDK.

Implement all required behaviors: TXT/RTF import, editing and safe native saves, adjustable typography, continuous speed control, play/pause, position-preserving relayout, independent horizontal/vertical reflection, a separate selectable output display, offline-capable iCloud document handling, and the R10–R16 operator features: a floating always-on-top prompter window, a compact control panel, speed in lines per minute, paragraph/restart/reverse/scrub navigation, remappable clicker and foot-pedal keys, timing aids (countdown, elapsed/remaining, Timed Scrolling), and reading aids. Keep source formatting, local display settings, and playback state separate. Cloud changes must never replace the snapshot used by a running take.

Proceed through the handoff's milestones. Do not stop at a plan, a nonfunctional scaffold, or a fake cloud adapter. Start with runnable local playback and deterministic timing tests, then complete import/persistence, output, cloud integration, and hardening. Keep dependencies minimal and document material deviations.

Run the tests and builds available in this environment. If macOS/Xcode, signing credentials, physical displays, or a second Mac are unavailable, complete the code and other checks that are possible, then identify the precise unverified scenarios. Never claim hardware smoothness, AppKit compilation, or real iCloud synchronization without evidence. Provide a local build configuration that does not require iCloud signing and document the owner-supplied cloud configuration.

Deliver the application source/project, tests, fixtures, README, architecture notes, iCloud setup guide, manual test plan, and implementation status. End with requirements coverage, changed files, actual executed commands/results, and remaining limitations. Do not request clarification for minor naming, visual, or layout choices already covered by the handoff.
