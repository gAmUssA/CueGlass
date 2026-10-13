# CueFlow — Codex implementation handoff

**Prepared:** October 13, 2026  
**Product:** A native macOS teleprompter with TXT/RTF import, smooth scrolling, independent external-screen output, and iCloud document synchronization.  
**Naming:** CueFlow is a working name. Brand, trademark, domain, and App Store availability have not been checked.  
**Status:** Specification and implementation instructions, not an implemented or benchmarked application.

## 1. Assignment

Implement CueFlow in the available repository. This is an implementation task, not a request for another research report or a plan-only answer.

First inspect the repository, its instructions (including AGENTS.md), working-tree changes, and available development environment. Preserve unrelated user work. Integrate into an existing application when appropriate; do not create a competing project without a reason. For an empty repository, create a native Mac application and its tests.

Use the engineering defaults below unless the existing project or measured behavior justifies an alternative. Do not block on naming, colors, or minor UI decisions. Document material deviations. Build through the milestones rather than stopping at a scaffold.

When the environment lacks macOS, Xcode, signing credentials, an external screen, or a second Mac, complete the work that can be completed and identify exactly what remains unverified. Never claim that a Linux core test proves AppKit works, that mocked file changes prove iCloud works, or that a display link alone proves smooth scrolling.

## 2. User requirements — mandatory for version one

| ID | Requirement | Expected behavior |
|---|---|---|
| R01 | Native macOS application | Normal Mac application, menus, windows, file dialogs, and keyboard behavior. |
| R02 | Import text files | Open or drop TXT; preserve text, paragraph breaks, and Unicode. |
| R03 | Import RTF documents | Preserve text and supported formatting; explain failures or unsupported content. |
| R04 | Synchronize between Macs using iCloud | Native script documents saved to iCloud become available on another Mac using the same account. |
| R05 | Customize fonts and text size | Font family and size controls alter presentation without destroying source formatting. |
| R06 | Faster/slower scrolling | Continuous speed control plus precise adjustment; explicit play and pause. |
| R07 | Smooth scrolling | Time-based, display-linked playback with stable speed across refresh rates. |
| R08 | Reflect text | Independent horizontal and vertical reflection, including both together. |
| R09 | Present on another screen | Separate clean output window on a selectable display; operator controls remain readable. |

### Assumptions and recommended defaults

These are implementation decisions, not additional requirements explicitly approved by the user.

- Minimum deployment target: **macOS 14.0**. Use the installed stable Xcode/Swift toolchain and record the versions actually tested.
- SwiftUI for controls and inspectors; AppKit for document/window ownership and the text viewport.
- Prefer TextKit 2 for the presentation renderer; verify the selected APIs against the installed SDK.
- NSDocument owns document opening, saving, autosaving, and coordinated access. Do not add a competing DocumentGroup lifecycle for the same documents.
- A view-associated CADisplayLink drives playback; verify availability and signatures in the SDK. [A1, A2]
- iCloud Drive synchronizes self-contained documents. Do not introduce a custom cloud backend or a CloudKit database for this scope.
- One active presentation session per app, even with multiple documents open.
- The output display is attached to the presenting Mac using an extended desktop. Synchronizing another Mac does **not** mean using iCloud as a live remote-control transport.
- Standard document Open/Save and Recents are sufficient initially. A custom script-library browser is optional.

### Out of scope

Speech-following, recording, camera/microphone access, AI writing, iPhone/watch clients, live remote control, collaborative editing, DOCX/PDF import, RTFD attachments, subscriptions, analytics, global input monitoring, and a full word processor. Cue markers, WPM estimates, and export convenience features can follow the required functionality.

## 3. Primary user experience

The user creates or imports a script, edits basic rich text, chooses reading typography, selects an output screen, configures reflection, and presses Play. Speed can change live. Font/layout changes preserve the text at the reading guide and leave playback paused. Saving to iCloud makes the document available on other Macs after synchronization.

The operator window contains the editor, transport controls, a compact settings inspector, and a preview. The output window contains only the presentation background, script, and optional reading guide. Errors, settings, and editing controls stay off the output screen.

Use native controls and accessible labels. Respect system appearance in the operator interface; default the presentation to light text on a dark background.

Suggested starting values, all configurable:

| Setting | Initial value | Proposed range |
|---|---|---|
| Font | System sans serif | Installed families |
| Font size | 64 pt | 18–180 pt |
| Line-height multiplier | 1.3 | 1.0–2.0 |
| Text column width | 70% of logical output width | 25–100%, with sensible padding |
| Scroll speed | 40 layout points/second | 1–300 points/second |
| Reading guide | 35% from logical viewport top | Adjustable or hidden |
| Reflection | Neither axis | Horizontal and vertical independently |

These numbers are starting choices, not performance or readability research findings. Pause is a distinct state, not a near-zero speed.

Provide a slider plus numeric speed adjustment. Suggested playback shortcuts: Space for play/pause, up/down for speed, Escape to exit output. Scope them carefully: typing spaces, navigating text, or editing a numeric field must not trigger transport commands.

## 4. Architecture and state ownership

Separate the following state domains:

| Domain | Contents | Persistence |
|---|---|---|
| Script document | Stable ID, title, authored RTF, saved reading style, preferred starting speed | Native document; syncs when stored in iCloud |
| Machine configuration | Output selection, reflection settings, window geometry, local defaults | Local preferences only |
| Playback session | Immutable text snapshot, snapshot ID, timeline, reading anchor, running/paused state | In memory; never saved every frame |

### Non-negotiable invariants

**An active take uses a stable snapshot.** Cloud reloads or editor changes must not replace text mid-take. For version one, making the editor read-only while playing is acceptable. An incoming update may replace the editable document model, but the operator sees an update notice and must explicitly load it while paused. Pause/resume alone must not select a new revision.

**Presentation styling is derived.** Changing font size or normalizing typography must not flatten the source RTF or erase authored emphasis. Save reading preferences separately from source content.

**All views sample one timeline.** Two display links must not increment one shared offset twice. Sampling a position is side-effect free.

### Suggested components

- `ScriptDocument`: NSDocument subclass; native read/write, undo/change tracking, save/reload integration.
- `ScriptImporter`: shared TXT/RTF pipeline for file dialogs and drag/drop, with diagnostics.
- `PresentationBuilder`: normalized or source-preserving attributed text derived from authored content.
- `PlaybackTimeline`: deterministic clock/position math without AppKit dependencies.
- `PlaybackSession`: stable snapshot, transport state, layout changes, and position management.
- `PrompterViewport`: non-editable AppKit renderer and scrolling viewport.
- `DisplayLinkDriver`: link creation, timing conversion, callback forwarding, and teardown.
- `ReadingAnchorResolver`: text-to-geometry mapping across relayout.
- `OutputWindowController`: display selection, clean output, disconnect and close handling.
- `DocumentStorageService`: container availability and file metadata outside document-owned saves.
- `LocalSettingsStore`: machine-specific settings.

Use appropriate actor isolation for AppKit/UI objects. Avoid unjustified `@unchecked Sendable` workarounds. Keep text-view mutation on the main actor and perform file work outside rendering callbacks, using framework-supported concurrency patterns.

## 5. Native documents, importing, and editing

### Native file format

Use `.cueflow`, initially represented as one versioned JSON document containing RTF data and reading metadata. Codable Data can carry the RTF payload as base64. The document is self-contained; an absolute path to an imported original must not become its authoritative content.

Logical schema:

```text
formatVersion: integer, initially 1
documentID: UUID
title: string
content:
  format: "rtf"
  data: Data
readingStyle:
  mode: "normalized" | "preserveSource"
  fontIdentifier: optional string; nil means system font
  fontSize: number
  lineHeightMultiplier: number
  paragraphSpacing: number
  columnWidthFraction: number
  foregroundRGBA: four numbers
  backgroundRGBA: four numbers
  readingGuideFraction: number
  showsReadingGuide: boolean
preferredSpeedPointsPerSecond: number
```

Validate schema version, payload size, finite numeric values, ranges, and RTF decoding before replacing content. Reject unsupported future versions without overwriting them. Default optional fields explicitly. Snapshot IDs and local timestamps are not distributed conflict-resolution clocks.

Register the native extension, document class, and uniform type correctly. A local prototype can use a clearly provisional identifier such as `com.example.cueflow`; make the real bundle identifier, signing team, and iCloud container configurable. Do not commit signing credentials, certificates, private account details, or invented ownership claims.

### TXT import

Support strict UTF-8 and BOM-declared UTF-8/UTF-16. When decoding is ambiguous or fails, offer an encoding choice rather than silently replacing characters. Normalize CRLF/CR to LF without deleting blank lines or punctuation. Test Cyrillic, emoji, combining characters, and mixed writing directions.

### RTF import

Use NSAttributedString's explicit RTF document-reading API, not a custom parser or external converter. [A3] Preserve text, bold, italic, supported colors, and basic paragraph structure. Detect supported categories of complex content such as attachments/tables and explain any proposed simplification before discarding meaningful content.

Document the supported subset honestly. Successful decoding does not prove full word-processor fidelity, and unsupported-formatting detection may itself be limited. RTFD, DOCX, and PDF remain unsupported imports.

TXT/RTF import creates a new native document and leaves the original untouched. Opening `.cueflow` opens it in place. Both dialog selection and drag/drop use the same pipeline. Handle empty, malformed, unsupported, and oversized files without losing the previously loaded document. Choose and document a defensive import-size limit; do not truncate silently.

### Editing and reading styles

Provide ordinary text selection, clipboard, undo/redo, and basic emphasis editing through an AppKit editor. The presentation view is separate and non-editable.

Normalized mode applies the selected font/size/colors while preserving bold/italic traits where possible. Preserve-source mode retains supported source styling with a presentation scale. Define spacing consistently in both modes. Missing fonts use a clear fallback with an operator notice. Do not distribute or synchronize font files.

## 6. Playback — prove this early

### Timeline math

At a constant velocity:

```text
position(t) = anchorPosition + velocity * (t - anchorTime)
```

Use layout points per second, fractional positions, and a monotonic clock. Never mix wall-clock Date values with display-link timestamps. Define and test the clock conversion at the platform boundary.

At a speed change, evaluate the old timeline at the change time, install that position as the new anchor, then change velocity. Pause freezes position; resume rebases time. Seeking, restart, and relayout rebase explicitly. Reject nonfinite values, invalid times, and unsupported velocities.

Every viewport samples the same timeline for its presentation time. Keep this math in a Foundation-only package with an injectable clock. Do not equate a frame count to elapsed time.

### Display-linked rendering

Use the relevant NSView's display-link creation API rather than assuming an iOS constructor. A view-associated display link follows that view's display; `targetTimestamp` supplies upcoming presentation timing. Verify exact signatures in the installed SDK. [A1, A2, A4]

Choose a main-run-loop mode that does not stall playback during control tracking. Each callback should sample position and move the viewport without implicit animation. It must not parse RTF, rebuild the attributed string, save files, synchronize cloud data, or broadcast the entire document through SwiftUI every frame.

Pause unused links and invalidate on teardown. Prevent target/controller retain cycles with a sound ownership design or weak forwarding target. Relying only on deinit is insufficient if a cycle prevents deinit.

Start with a layer-backed, non-editable NSTextView inside NSScrollView. Measure low-speed movement on hardware. If the chosen scrolling path quantizes positions visibly, add a renderer-level fractional translation or cached-fragment strategy. Do not declare smoothness merely because CADisplayLink is present, and do not jump straight to Metal without evidence.

Prefer TextKit 2 deliberately. Audit legacy `layoutManager` access that may trigger compatibility fallback. [A5] A justified explicit TextKit 1 renderer is preferable to accidental mixed-mode behavior; isolate and document such a deviation.

TextKit 2 uses viewport-oriented layout and can estimate offscreen geometry. [A6] Prepare a bounded region ahead of playback. Do not relayout a long document every frame or use an estimated total height as the definitive end condition. Stop after the actual final text and intentional trailing space reach the end position.

### Reading anchors

Before changing size, family, spacing, or logical output width, pause and capture the text under the reading guide. Use a snapshot-scoped text location, such as a valid UTF-16 offset, plus an intra-line position where useful. Respect grapheme/surrogate boundaries and distinguish Swift character counts from AppKit ranges.

Relayout, find the same text, restore it to the guide, and rebase the timeline. Stay paused after layout changes in version one. Speed changes remain live and must not relayout. Do not reuse a snapshot anchor blindly after arbitrary edits or document replacement.

### Stalls and lifecycle

Pause and retain the last safely presented position on sleep or output loss. For long callback stalls, use a documented threshold—0.5 seconds is a proposed starting point—to pause rather than jump ahead. Ordinary dropped frames use elapsed time.

Monitor the active presentation output, not an occluded operator preview. Minimizing the operator window must not interrupt an external presentation. When there is no external output, designate the local presentation as authoritative. Update progress labels less frequently than rendering, and avoid busy work while paused.

## 7. External output and mirroring

Populate a user-facing display picker from NSScreen. Do not assume array index 1 identifies the desired monitor or persist an array index as display identity. Stored display identification is a best-effort preference, not a guarantee.

Create a separate borderless screen-filling output window with a reliable Escape/Stop Output action. Native fullscreen Spaces are optional. Use the selected screen's complete frame and support negative desktop coordinates and different backing scales. Keep the operator window independently usable.

The active output owns the logical layout specification. The operator preview scales that layout; it must not independently rewrap to its own window width and reuse an unrelated vertical offset. The regular operator preview can remain readable/unmirrored; provide an actual-output calibration mode.

Apply independent transforms around the presentation viewport center:

```text
scaleX = reflectHorizontally ? -1 : 1
scaleY = reflectVertically   ? -1 : 1
```

Do not reverse string characters. Applying both reflections is equivalent to a 180-degree rotation. AppKit's flipped coordinate convention is not visual mirroring. Keep controls and the editor outside the transform. Make output noninteractive except for exit, or correctly invert coordinates for interactions.

Logical scroll direction remains separate from reflection. Supply an asymmetric calibration fixture with words, numbered lines, LEFT/RIGHT labels, and UP/DOWN arrows. Validate all four reflection combinations through the intended optical setup.

Observe display configuration changes and output closure. If the selected screen disappears, pause, retain position, and prompt for a new selection in the operator window. Do not silently cover the editor with mirrored text. Opening another document must not create an uncontrolled second presentation session.

## 8. iCloud synchronization

### Document lifecycle and storage

Use NSDocument and iCloud Drive. NSDocument participates in coordinated access and standard document-version conflict handling. [A7, A8] Do not implement a second save path, rewrite open files from a filesystem watcher, or add nested manual coordination around framework-owned saves.

Implement native reading/writing, autosaves-in-place, undo/change tracking, and safe reload handling. Playback position changes must not dirty the document each frame.

Offer explicit On This Mac and iCloud storage choices. Discover the entitled container with `FileManager.url(forUbiquityContainerIdentifier:)`; never hard-code a Mobile Documents path. [A9] Keep potentially blocking discovery/download work out of the render loop and off the UI thread where supported. A nil/unavailable container must not lose an unsaved document.

Standard document panels are sufficient initially; a custom NSMetadataQuery library is not mandatory. [A7]

### Build/account setup

Provide a local development configuration that does not require iCloud signing and an iCloud-enabled configuration using owner-supplied signing settings. Local mode must say that integrated iCloud storage is not configured; it must not simulate cloud success.

Configure document types, sandbox user-selected access, iCloud Documents/container settings, and required entitlements. Verify the actual configuration through the installed SDK/Xcode capabilities. Keep identifiers consistent and configurable. Missing credentials may block real cloud tests but should not block local implementation or writing the integration code.

### Offline use and truthful status

Locally available scripts must open and play offline. Cloud-only files need an explicit downloading/unavailable state. Request download with the platform APIs when appropriate; start playback only after the complete snapshot is available.

Show only states supported by actual resource metadata: local, saved locally, pending/uploading when knowable, downloading, unavailable, error, or unknown. A completed save is not evidence that another Mac received the file. Do not fabricate remote acknowledgment or progress.

Handle iCloud identity/account changes and unavailable containers. Preserve unsaved edits and offer explicit local saving. Do not silently migrate, duplicate, delete, publish, or share documents when account state changes.

### Conflicts and take isolation

Use the document framework's standard version/conflict workflow first. Do not choose a winner from client timestamps or implement an automatic RTF merge. Preserve recoverable versions and a save-copy path before discarding edits. Verify the actual conflict UI and recovery behavior on the target systems. [A8]

Remote content changes update the editable document, never the active immutable take. Loading newer text requires an explicit action while paused. Test a simulated replacement and then a real two-Mac edit conflict.

Sync authored content and saved reading preferences. Keep output selection, reflection, window geometry, security-scoped references, and live playback local. Global preference sync is optional. Do not put a live SQLite database into iCloud Drive as a substitute for a supported database synchronization design.

## 9. Permissions, accessibility, and failure handling

Use normal user-selected file access. Apply security-scoped access/bookmarks where required and balance successful starts/stops. [A10] Importing a self-contained document should not require permanent access to its original. Do not request Full Disk Access.

The baseline needs no camera, microphone, screen-capture, or global-input monitoring. Use application-local commands. No analytics; do not log script contents, private paths, credentials, or iCloud identities.

Errors preserve the previous good document/session. Handle malformed files, missing fonts, failed saves, unavailable cloud state, and lost screens with readable operator-only messages. Avoid force unwraps for user-controlled input. Give controls accessible labels and logical focus order, and retain normal text-editing behavior.

## 10. Repository and deliverables

Suggested structure; adapt to an existing project rather than reorganizing gratuitously:

```text
CueFlow.xcodeproj/
CueFlow/
  Application/
  Documents/
  Import/
  Editor/
  Presentation/
  Playback/
  Output/
  Storage/
  Settings/
  Resources/
Packages/CueFlowCore/
  Package.swift
  Sources/CueFlowCore/
  Tests/CueFlowCoreTests/
CueFlowTests/
CueFlowUITests/
Fixtures/
Configuration/
docs/
  ARCHITECTURE.md
  ICLOUD_SETUP.md
  MANUAL_TEST_PLAN.md
  IMPLEMENTATION_STATUS.md
README.md
```

Deliver a real Xcode project with a shared scheme, or a deterministic documented generation path. Do not deliver only disconnected snippets. Prefer no third-party dependencies unless a specific need justifies one.

Include UTF-8/UTF-16, Cyrillic/emoji, rich RTF, calibration, malformed, and generated large-script fixtures. Use original synthetic content rather than copyrighted sample scripts.

README must cover the actual toolchain, local build, tests, import, playback, external display selection, reflection, and iCloud setup. Record architecture decisions, known limitations, and actual validation evidence. Do not present pending hardware checks as completed.

## 11. Implementation milestones

### M0 — Runnable foundation

Create the app shell, document structure, core package, operator UI, and fake-clock timing tests. Verify a local launch when macOS/Xcode is available.

**Exit:** an in-memory sample appears in a presentation viewport and core timing tests pass.

### M1 — Import and local documents

Implement TXT/RTF import, diagnostics, editing, native format round trips, undo, autosave, local Open/Save, and derived styling.

**Exit:** both import paths save/reopen correctly without altering original files.

### M2 — Dependable playback

Implement display-linked motion, live speed changes, pause/resume/restart, anchors, layout controls, cleanup, and stall handling. Prove very slow movement early.

**Exit:** timing/anchor tests pass and long-script local playback is demonstrated, or hardware verification is explicitly pending.

### M3 — External presentation

Implement output selection, independent window, shared logical preview layout, both reflection axes, calibration, and disconnect handling.

**Exit:** reflection and simulated disconnect tests pass; physical display results are recorded separately.

### M4 — iCloud documents

Complete configurations, container discovery, storage choice, status, offline/account handling, version conflicts, and active-take isolation.

**Exit:** real two-Mac sync is demonstrated where credentials/hardware exist. Otherwise code, tests, setup steps, and the precise validation blocker are delivered. Do not label it fully verified.

### M5 — Hardening and documentation

Finish focus-safe shortcuts, accessibility, recovery, lifecycle/profiling checks, fixtures, and build/setup documentation. Describe signing/notarization steps; do not claim a notarized build unless actually produced and verified.

**Exit:** every R01–R09 requirement maps to an implementation and evidence or a concrete remaining blocker.

## 12. Acceptance tests

These are proposed tests, not measured performance claims.

| Check | Required outcome | Level |
|---|---|---|
| Timeline at several velocities | Correct fractional positions with a documented numeric tolerance | Unit |
| 60 Hz vs 120 Hz sampling | Same position at equal logical time | Unit |
| Two viewport readers | Sampling does not mutate or double-advance playback | Unit |
| Mid-run speed changes | Continuous position | Unit |
| Pause for 30 seconds | No movement during pause or jump on resume | Unit |
| Invalid input values | No NaN propagation, crash, or unsupported position | Unit |
| Native format round trip | ID, content, and style survive | Unit/integration |
| Malformed/future format | Clear rejection, previous content preserved, no overwrite | Integration |
| Unicode/encoding fixtures | Accurate import or explicit recovery, not silent loss | Unit/integration |
| Typography changes | Source RTF unchanged; same anchor remains near the guide | Integration/visual |
| Very slow scrolling | No persistent visible stepping or repeated layout jumps | Hardware |
| Mixed-refresh output/preview | Stable reading speed and aligned logical content | Hardware |
| 100,000-word script | Bounded per-frame work; no whole-document rebuild loop | Profiling |
| 60-minute session | No progressive memory growth or accumulating timing error | Profiling/hardware |
| Repeated pause/close cycles | Display links/windows released; paused state not busy | Integration/profiling |
| All four reflection settings | Correct optical output; source/editor unaffected | Visual/physical |
| Negative desktop origin/scaling | Correct output position and rendering | Hardware |
| Disconnect/sleep | Safe pause at retained position; no catch-up leap | Integration/hardware |
| Hidden operator window | External presentation continues | Hardware |
| Editor spaces/arrows | Normal editing, not playback commands | UI |
| Save on Mac A, open on Mac B | Content and saved reading style transfer after actual sync | Two-Mac iCloud |
| Both Macs edit offline | Conflict recovery preserves recoverable work | Two-Mac iCloud |
| Cloud change during take | Take remains unchanged until explicit paused reload | Integration/two-Mac |
| iCloud unavailable/cloud-only file | Honest state and safe local behavior | Integration/iCloud |

Profile release builds on actual hardware. Record OS, machine, display refresh rates, fixture size, timing, and layout spikes. A proposed steady-state rendering callback goal is under 2 ms on the tested machine, excluding deliberate relayout; treat it as a goal, not a universal guarantee. Never fabricate benchmarks.

Example checks to adapt to the actual generated project:

```sh
swift --version
swift test --package-path Packages/CueFlowCore
xcodebuild -version
xcodebuild -list -project CueFlow.xcodeproj
xcodebuild -project CueFlow.xcodeproj -scheme CueFlow \
  -configuration DebugLocal -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the actual test scheme with appropriate configuration and host signing. Unsigned compilation does not validate sandbox behavior or iCloud. Record exact executed commands and their results, not just proposed commands.

## 13. Completion report

At the end of implementation, provide:

1. Implemented behavior mapped to R01–R09.
2. Actual build/test commands, environment, and results.
3. Important files, architecture choices, and justified deviations.
4. Account/signing setup still required from the owner.
5. Separate automated, manually verified, and unverified hardware/cloud checks.
6. Prioritized remaining limitations and blockers.

A placeholder Play button, fake sync-success indicator, fixed-distance timer scroll, destructive font resizing, or single-window-only implementation does not satisfy the handoff. Honest partial completion is preferable to a misleading production-ready claim.

## 14. Primary implementation references

These references support the proposed platform choices; they do not establish that CueFlow has been built or tested. Verify signatures, availability, and configuration against the installed SDK. Some architecture references are archived Apple material and should be checked against current Xcode behavior.

- **A1:** [NSView displayLink(target:selector:)](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)) — view-associated display-link creation.
- **A2:** [WWDC23: What's new in AppKit](https://developer.apple.com/videos/play/wwdc2023/10054/) — display-linked rendering in AppKit.
- **A3:** [NSAttributedString document-reading initializer](https://developer.apple.com/documentation/foundation/nsattributedstring/init(data:options:documentattributes:)) — attributed document import.
- **A4:** [CADisplayLink targetTimestamp](https://developer.apple.com/documentation/quartzcore/cadisplaylink/targettimestamp) — upcoming presentation timing.
- **A5:** [WWDC22: What's new in TextKit and text views](https://developer.apple.com/videos/play/wwdc2022/10090/) — text system choices and compatibility.
- **A6:** [WWDC21: Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/) — viewport-oriented text layout.
- **A7:** [Designing for Documents in iCloud](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html) — document-based cloud architecture.
- **A8:** [Apple Technical Note TN2336](https://developer.apple.com/library/archive/technotes/tn2336/_index.html) — iCloud file/version conflict handling.
- **A9:** [iCloud Fundamentals](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html) — container and account concepts.
- **A10:** [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — scoped file access.
