# Manual validation plan

Record OS/build, Mac model, scale/refresh rates and synthetic fixture size. Do not record private display UUIDs, account identities or script contents. Status of every procedure below: pending unless separately entered with observed evidence. Automated AppKit results and current implementation evidence are in [implementation status](IMPLEMENTATION_STATUS.md); they do not establish physical acceptance.

## Local document and accessibility

Before focus or accessibility validation, confirm the console session is unlocked and CueGlass becomes the active app with a key document window. A locked console can leave a visible native window inactive and return unusable external AX window entries. Record this as blocked; do not infer accessibility from cached text, unlock the operator's session, or change privacy settings. Use a separate-process AX walk on the launched app to check elapsed/remaining captions and values, LPM, and the locked-editing banner in a paused take. Then exercise native menu Undo/Redo and editor/inspector versus transport focus.

Build DebugLocal, Run in Xcode, import each committed fixture through Open and drop. Generate binary/large fixtures with `swift scripts/make-fixtures.swift`. Compare TXT/RTF original bytes/mtime; they must not change after editing, Save, close and reopen native. Verify Unicode/blank paragraphs and bold/italic/color. Invalid UTF-8 must offer an encoding preview; Cancel leaves existing work. RTFD/PDF/DOCX/malformed/oversize must fail without loss. Unsupported RTF content must be disclosed and retained in source. Undo/Redo must restore content and reading style; close/reopen and autosave recovery must retain the last good edit.

Navigate editor → transport → inspector → preview with Tab/VoiceOver. Every control must have a meaningful label and a visible keyboard focus. Type spaces and use arrows in editor and numeric speed/size fields: no playback action. With preview focus, Space/Up/Down must control transport. Check option-command menu shortcuts, Escape from each focus location with output present, native clipboard, fonts, Recents and system light/dark appearances. The preview screenshot captured by tests is an offscreen cache render, not a full WindowServer fidelity claim.

## Playback and relayout

At 1, 5, 40 and 300 pt/s, observe low-speed motion on 1× and 2× screens. Compare fractional translation on/off in a development build. Pass: no persistent visible stepping or repeated layout jumps. Retain measurements before changing renderer strategy. Pause for 30 seconds, resume, change speed between frames and restart: no catch-up jump or backward step.

At a named word under the guide, change family/size/spacing/width/guide. Pass: same text remains within one line and playback stays paused. Source RTF must retain emphasis. Load a new revision while running: snapshot remains unchanged; Load Latest is disabled. Pause/resume alone must keep the take. Explicit Load Latest resets changed text and carries an identical-text anchor.

Generate the 100,000-word fixture. Profile ReleaseLocal for 60 minutes with Instruments Time Profiler/Allocations/Core Animation. Record callback p50/p95/max, memory start/end, layout spikes and display rates. Pass: bounded steady-state work, no whole-document per-frame rebuild, no progressive memory growth or accumulating drift. Under-2-ms steady-state callbacks are a measurement goal, not a claim or universal guarantee.

## Output hardware and lifecycle

Compare the complete fullscreen background, including both margins outside the text panel, with the preview at default and changed background colors. Repeat with text-panel opacity at 25% and 0%; the fullscreen matte must remain the selected background. In floating mode, confirm whole-window opacity and text-panel opacity remain independent and the margins remain transparent.

Use extended desktop with mixed refresh rates and at least one negative-origin display. Select each named screen. Pass: output covers its complete frame, contains only text/background/guide, and preview wraps identically at scaled logical dimensions. Confirm the operator-screen warning. Disconnect selected output: retained-position pause, clear operator notice and no automatic editor-covering fallback. Reconnect requires explicit selection.

Hide/minimize/occlude operator while external output plays: output continues. Sleep/screens-sleep and wake: paused at the last safely presented text. Introduce a >0.5-second debugger stall: pause rather than leap. Normal short dropped frames retain time-based speed. Repeatedly Play/Pause/Stop and open/close output; inspect links/windows and memory for retention or paused busy work.

Use Calibration and intended optical glass. Check all four reflection combinations; UP/DOWN and LEFT/RIGHT plus numbered asymmetric lines must map correctly. Both together must match 180-degree rotation. Editor/controls remain readable. Check Escape and Stop Output with separate Spaces/Mission Control, menu bar and app deactivation. Output window level is a hypothesis until this passes.

## Signed sandbox and iCloud (two Macs)

Complete ICLOUD_SETUP.md with real owner values. Verify signed entitlements/processed plist. Save a script/style on Mac A to integrated iCloud; wait for actual metadata upload; open on Mac B and compare ID/content/style. Playback position, reflection, selected screen and geometry must remain local. Do not infer delivery from Mac A's save result.

With local bytes cached, disable networking and open/edit/play/save. With a dataless file, request download; the app must not prepare a take until complete. Disconnect account or switch identity with unsaved edits: retain edits, show honest state, allow explicit local copying and never silently move/delete files.

Edit the same document offline on both Macs. Reconnect, use Versions/conflict UI and Save a Copy before choosing. Pass: both recoverable versions remain accessible, no automatic timestamp winner and no RTF merge. If system conflict UI does not expose both, stop and report; do not remove conflicting versions. Deliver a change while a take runs: snapshot and position remain stable until explicit paused reload. Deliver formatVersion 2 while open: revert fails, old source stays, autosave cannot overwrite newer disk bytes, Save a Copy to another path succeeds.

## Expanded operator acceptance (R10–R16)

Run current-tip full independent tests before checking any MVP box. Verify the unified toolbar, three panes and disclosure groups at 980, 1002 and 1280 pt. Open inspector at minimum width; it must grow within the screen or stay usable/collapsed, with no unsatisfiable constraints. Inspect actual light/dark and Increase Contrast/Reduce Transparency/Reduce Motion. Cached renders are incomplete; screen capture requires separately available permission, never a reason to fabricate a pass.

Record actual outer-window frames at 1280×800 and 1002×800. Check the take bar, first editor line and inspector top against the titlebar pockets in an owned-window capture. Record the 980 resize result, collapsed inspector state and re-expansion at 1002; a sequence of external resize requests is not continuous-drag proof. The declared minimum is 980×640. With the toolbar attached, the current AppKit host reports a 660 pt height floor, a 20 pt toolbar delta; record the settled frame height.

With the operator hidden, use Controls, B/period, Page Up/Down, Home, R, fine/jump arrows and remapped keys. Check reserved/conflicting shortcuts reject and reset/persistence work. Edit inspector numeric fields and script text; keys must retain editing behavior. Verify Show Operator and menu routes while Controls is key. Physical keyboard-emulating pedals/clickers need their own evidence with the app targeted/frontmost.

At 30 LPM, change font size 18→64→120→180 and line height 1→2; same text stays within one guide line and nominal LPM stays unchanged. Check Preserve Source headings/relative sizes and authored RTF bytes. Try a tall installed font at high pace: display effective limited pace, keep nominal saved preference and remain finite.

Use Timed Scrolling on actual measured end with 300 seconds, pause/resume, scrub/step and relayout. Pass: finish within one presented frame of target playing duration, exclude paused time, visibly reject impossible pace/duration, disable on manual speed/direction, hold at end/start and allow Restart. Countdown 3/5/10 must mirror, freeze text and cancel on toggle/restart/step/scrub/sleep/loss. Estimated remaining follows direction; Measuring/unknown remains honest before actual end.

Switch local/fullscreen/floating and resize floating while playing: one surface, immutable snapshot, same guide text and restored play state after measurement. Float over a real fullscreen call app, drag, move displays, disconnect and restore frame. Whole-window alpha must visibly affect the entire panel independently of text-panel alpha. Check warnings at low alpha and transparent ink. Exercise optional click-through and recovery by Controls, menu and Escape; low-alpha hit testing is unverified until observed. Controls must never sit on selected fullscreen output: safe other display or hidden with recovery, even when output used the operator screen.

Guide styles/opacity, edge gradient and text-panel opacity must not rewrap; margins must perform one anchored relayout. Test hide-while-playing after inactivity, restoration on pointer movement/pause/commands, and no fades under Reduce Motion. No operator timing/settings may appear on the clean output. Perform sustained 100k-word and 60-minute profiling separately from the paused measurement micro-observation.

## Follow Voice (macOS 26+)

Run on an unlocked macOS 26+ Mac with a human speaker. Record OS/build and device; do not write script or recognized speech into the test record. Synthetic speech is not acceptance evidence. Start from a fresh microphone privacy state for the prompt case. Verify the inspector is absent on macOS 14–25 and when SpeechTranscriber reports unavailable; a build targeting macOS 14 is not a runtime test on macOS 14.

Automated and review results (2026-10-14): the unsigned DebugLocal build targets `arm64-apple-macos14.0`; 41 Core tests and 70 native tests passed, including fake-source permission/model, clock-advanced manual-pause, surface-transition and TextKit mapping coverage. The available host was macOS 27.0.1. GitHub Actions run [38661758289](https://github.com/gAmUssA/CueGlass/actions/runs/38661758289) passed on `cce977e56fdd7e51d51319c36c824dec4a03683f`. A fresh scoped independent re-check on that tip cleared the four findings from the preceding review and found no new blocker. This scoped re-check is not a full review for release. These automated and source-review results do not complete any human-speech row below; every row remains pending until observed and recorded.

Read-only speech preflight on macOS 27.0.1: `SpeechTranscriber.isAvailable` was true; `supportedLocales` and `installedLocales` include `en_US`; `AssetInventory.status` for CueGlass's configured `en-US` transcriber was `.supported` (Apple defines this as supported with assets still requiring download; see [status](https://developer.apple.com/documentation/speech/assetinventory/status/supported)). A separate-process Accessibility read of the inspector confirmed Language is English (United States), the selected model needs installation consent, and the explicit Install Speech Model button is present. The DebugLocal microphone grant was reset for `com.example.cueflow` to prepare a fresh prompt, but no new prompt or denial result has been observed. No model installation or microphone capture was started; this preflight does not pass any human-speech row.

| Case | Required observation | Status |
|---|---|---|
| Availability and locales | UI is macOS 26+/supported-device only; select an offered locale; English is identified as validated | Pending |
| Permission prompt and denial | Start alone prompts; deny; no capture/listening starts; denial explains Settings path | Pending |
| Settings recovery | Open Privacy & Security → Microphone, allow CueGlass, retry Start successfully | Pending |
| Missing model consent | Capability check downloads nothing; Install is explicit; observe actual progress, cancel, and confirm no analyzer/mic start | Pending |
| Model installation | Consent to install, observe completion and readiness recheck, then separately Start | Pending |
| Silence and low confidence | Speak no words or indistinct words; follow holds without advancing and shows a clear waiting state | Pending |
| Ad-lib | Speak words absent from the script; position holds until confidence recovers | Pending |
| Skip and reacquisition | Skip ahead; confirm bounded glide/jump only after enough matching words | Pending |
| Reread and reacquisition | Read a prior passage; confirm policy reacquires without volatile-update jumps | Pending |
| Manual override and resume | Seek/step/change pace/direction/pause and switch preview/output/floating surfaces or resize floating; mic closes and status says paused; motion stays held until Play/Space or Resume explicitly restarts | Pending |
| Timed Scrolling separation | Choose Timed Scrolling while following; confirm microphone closes and voice session ends | Pending |
| Sustained human take and teardown | Run a long human take, then Stop Follow Voice/Stop Take/close/sleep; verify no retained audio/transcript and no live mic indicator | Pending |

No human-speech result is claimed yet. The scoped source review and CI gates now clear the corrected tip for operator testing. Do not check these rows based on the standalone generated-speech experiment, source review or automated tests.
