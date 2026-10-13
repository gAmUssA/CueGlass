# Manual validation plan

Record OS/build, Mac model, scale/refresh rates and synthetic fixture size. Do not record private display UUIDs, account identities or script contents. Status of every procedure below: pending unless separately entered with observed evidence. Automated AppKit results are in README, not physical acceptance.

## Local document and accessibility

Build DebugLocal, Run in Xcode, import each committed fixture through Open and drop. Generate binary/large fixtures with `swift scripts/make-fixtures.swift`. Compare TXT/RTF original bytes/mtime; they must not change after editing, Save, close and reopen native. Verify Unicode/blank paragraphs and bold/italic/color. Invalid UTF-8 must offer an encoding preview; Cancel leaves existing work. RTFD/PDF/DOCX/malformed/oversize must fail without loss. Unsupported RTF content must be disclosed and retained in source. Undo/Redo must restore content and reading style; close/reopen and autosave recovery must retain the last good edit.

Navigate editor → transport → inspector → preview with Tab/VoiceOver. Every control must have a meaningful label and a visible keyboard focus. Type spaces and use arrows in editor and numeric speed/size fields: no playback action. With preview focus, Space/Up/Down must control transport. Check option-command menu shortcuts, Escape from each focus location with output present, native clipboard, fonts, Recents and system light/dark appearances. The preview screenshot captured by tests is an offscreen cache render, not a full WindowServer fidelity claim.

## Playback and relayout

At 1, 5, 40 and 300 pt/s, observe low-speed motion on 1× and 2× screens. Compare fractional translation on/off in a development build. Pass: no persistent visible stepping or repeated layout jumps. Retain measurements before changing renderer strategy. Pause for 30 seconds, resume, change speed between frames and restart: no catch-up jump or backward step.

At a named word under the guide, change family/size/spacing/width/guide. Pass: same text remains within one line and playback stays paused. Source RTF must retain emphasis. Load a new revision while running: snapshot remains unchanged; Load Latest is disabled. Pause/resume alone must keep the take. Explicit Load Latest resets changed text and carries an identical-text anchor.

Generate the 100,000-word fixture. Profile ReleaseLocal for 60 minutes with Instruments Time Profiler/Allocations/Core Animation. Record callback p50/p95/max, memory start/end, layout spikes and display rates. Pass: bounded steady-state work, no whole-document per-frame rebuild, no progressive memory growth or accumulating drift. Under-2-ms steady-state callbacks are a measurement goal, not a claim or universal guarantee.

## Output hardware and lifecycle

Use extended desktop with mixed refresh rates and at least one negative-origin display. Select each named screen. Pass: output covers its complete frame, contains only text/background/guide, and preview wraps identically at scaled logical dimensions. Confirm the operator-screen warning. Disconnect selected output: retained-position pause, clear operator notice and no automatic editor-covering fallback. Reconnect requires explicit selection.

Hide/minimize/occlude operator while external output plays: output continues. Sleep/screens-sleep and wake: paused at the last safely presented text. Introduce a >0.5-second debugger stall: pause rather than leap. Normal short dropped frames retain time-based speed. Repeatedly Play/Pause/Stop and open/close output; inspect links/windows and memory for retention or paused busy work.

Use Calibration and intended optical glass. Check all four reflection combinations; UP/DOWN and LEFT/RIGHT plus numbered asymmetric lines must map correctly. Both together must match 180-degree rotation. Editor/controls remain readable. Check Escape and Stop Output with separate Spaces/Mission Control, menu bar and app deactivation. Output window level is a hypothesis until this passes.

## Signed sandbox and iCloud (two Macs)

Complete ICLOUD_SETUP.md with real owner values. Verify signed entitlements/processed plist. Save a script/style on Mac A to integrated iCloud; wait for actual metadata upload; open on Mac B and compare ID/content/style. Playback position, reflection, selected screen and geometry must remain local. Do not infer delivery from Mac A's save result.

With local bytes cached, disable networking and open/edit/play/save. With a dataless file, request download; the app must not prepare a take until complete. Disconnect account or switch identity with unsaved edits: retain edits, show honest state, allow explicit local copying and never silently move/delete files.

Edit the same document offline on both Macs. Reconnect, use Versions/conflict UI and Save a Copy before choosing. Pass: both recoverable versions remain accessible, no automatic timestamp winner and no RTF merge. If system conflict UI does not expose both, stop and report; do not remove conflicting versions. Deliver a change while a take runs: snapshot and position remain stable until explicit paused reload. Deliver formatVersion 2 while open: revert fails, old source stays, autosave cannot overwrite newer disk bytes, Save a Copy to another path succeeds.
