# CueGlass

A native macOS teleprompter for local, floating and selected-display presentation. macOS 14+, AppKit documents/windows and TextKit 2, SwiftUI inspector, Foundation-only timing/core contracts. No external runtime dependencies. The owner-facing name is CueGlass; the unreleased `.cueflow` document contract remains unchanged in name and version.

## Build and run

Validated: Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428), arm64. Open the committed `CueFlow.xcodeproj`, shared CueFlow scheme, DebugLocal. Local ad hoc signing needs no Apple development team or iCloud credentials.

```sh
xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugLocal \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode build
open .build/Xcode/Build/Products/DebugLocal/CueFlow.app
```

Quit with Command-Q. `project.yml` generates the real committed project/shared scheme with XcodeGen 2.46.0 (`xcodegen generate`); generation is optional for building. Generated project files are marked in `.gitattributes`. Build products, owner files and generated binary/large fixtures are ignored.

## Read and present

Open/drop TXT, RTF or `.cueflow` onto the editor. TXT/RTF imports create unsaved native documents and leave originals untouched. File → Save stores source RTF, stable identity and reading preferences in versioned self-contained JSON. Native clipboard, Undo/Redo, Bold/Italic and Fonts remain available. Imported source attributes are preserved; derived presentation styling never flattens authored RTF.

The unified toolbar carries Restart, paragraph back, Play/Pause, paragraph forward, Reverse and Present. The dark stage scales the exact logical output instead of independently wrapping. The collapsible inspector groups typography, reading guide, reflection, layout/colors, floating options, timing and keys. At 980 pt the inspector collapses; opening it grows toward 1002 pt within the screen. Storage actions live in File and the truthful window subtitle.

Choose pace in **lines/minute**, with estimated WPM from actual laid-out lines. Typography preserves nominal LPM and the text under the guide, leaving playback paused. Base line advance is the presentation base font's natural height × line-height multiplier, excluding paragraph spacing; larger Preserve Source runs pass more slowly. Normal supported system-font sizes 18–180 pt and multipliers 1–2 are tested against actual line pitch. A pathological layout can reach the 2000 pt/s safety ceiling; the effective limited pace is labelled without silently changing the saved preference.

Present offers selected-screen fullscreen output or a floating draggable/resizable prompter. Only one surface presents at a time; switching or finishing floating resize carries the anchor and playing/paused state. Whole-window opacity is 30–100% (85% default), separate from text-panel opacity. Low worst-case composited contrast warns instead of silently clamping. Optional click-through applies only while playing and clears on pause. Escape, Controls or the menu recover control. Frames persist relative to each display and clamp to a visible screen on restore/loss.

View → Controls opens a small HUD with restart, paragraph steps, Play/Pause, direction, elapsed/remaining, fine/jump pace steps, slider and Show Operator. It works with the operator hidden and is placed away from fullscreen output; if no safe display exists it hides, leaving keyboard/menu recovery. Floating mode serves single-display use. Hide-controls restores on pause, a command or pointer movement and respects Reduce Motion.

Default app-local commands: Space/B/`.` play-pause; Up/Down fine pace; Shift-Up/Down jump; Page Down/Right and Page Up/Left paragraphs; Home/Command-Up restart; R reverse; Escape stop presenting. Editor/inspector text and focused controls keep ordinary editing. Remap keys, reset defaults and configure pace limits/steps in Controls & Keys. Reserved Mac shortcuts and conflicts are rejected. The app must be frontmost or a clicker/keyboard-emulating pedal must target it; no global event monitor exists. Menu recovery includes Option-Command-P, Option-Command-O and Option-Command-K.

Timing includes a cancellable mirrored 3/5/10-second countdown, elapsed playing time, direction-aware remaining time and Timed Scrolling to the actual forward end. Duration is seconds (up to 10 hours); impossible pace/duration requests explain why. Manual pace/direction changes disable Timed mode visibly. Navigation/relayout recomputes against remaining playing duration. Restart returns forward/start/paused and resets elapsed. Outward playback holds at either bound.

Guide line/triangles, opacity, gradient edge fade, margins and text-panel opacity are configurable. Static reading-aid changes avoid text relayout; margins use guide-anchor restoration. Source snapshots remain immutable across pause/resume, editor/cloud reloads and surface changes. Explicit paused Load Latest adopts a new revision transactionally; failures keep the old take. Stop Take unlocks editing.

## Documents, recovery and iCloud

TXT limit 8 MiB; RTF 16 MiB; native JSON 32 MiB with a 16 MiB RTF payload. Regular-file/size checks run before and after reads. Strict UTF-8 and BOM UTF-8/UTF-16LE/BE preserve Unicode and blank paragraphs. Ambiguous encodings offer an explicit preview/choice. RTF uses the native explicit RTF API, preserving supported emphasis/fonts/colors/paragraphs. Attachment/table/link diagnostics explain presentation simplification; unsupported content stays in source. RTFD/DOCX/PDF are unsupported. No word-processor fidelity claim is made.

A rejected on-disk revision (malformed, future, unreadable, oversize or invalid payload) blocks overwriting saves while preserving the source/take and a different-path Save a Copy recovery route. Versions remains the native conflict workflow; the app never chooses a timestamp winner, merges RTF or deletes conflict versions automatically.

File → Save to iCloud uses FileManager's entitled container and NSDocument saves. [Owner setup](docs/ICLOUD_SETUP.md) supplies real team/bundle/container and plist key. Local mode explicitly says not configured. The effective DebugICloud/ReleaseICloud settings select the owner plist; unsigned processed-plist checks with a synthetic build-only container pass. This is not signing or real cloud proof. Uploaded means server upload only, never another Mac's receipt. Cloud-only opens request download and require reopen when complete. Account changes keep edits and offer local recovery.

Version 1 now reads/writes `preferredSpeedLinesPerMinute` only (missing = 30); the legacy pt/s key is ignored because no documents have shipped. Missing style fields default explicitly; unknown style enum tokens default with diagnostics, finite ranges clamp with notice, nonfinite values reject. Weight/system-design fields are derived preferences and never replace authored fonts in stored RTF.

## Verification and limits

```sh
swift test --package-path Packages/CueFlowCore --scratch-path .build/core
CUEFLOW_EPHEMERAL=1 xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugLocal \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
scripts/test-app.sh # optional direct-runner cross-check
xcrun swift-format lint --strict --recursive CueFlow Packages/CueFlowCore/Sources \
  Packages/CueFlowCore/Tests CueFlowTests scripts/make-fixtures.swift Packages/CueFlowCore/Package.swift
beans check --json
swift scripts/make-fixtures.swift
```

Developer evidence: **14 core Swift Testing tests and 20 native AppKit tests pass**. They cover LPM/schema/defaults, direction/bounds/pure sampling, command persistence/guards, timing/navigation/scrubbing, real line pitch, source-safe styling, transactional reloads, native save/undo, imports, native geometry at 980/1002/1280, hidden-operator panel commands, reading-aid relayout counts and chunked actual-end measurement. The adapted independent supplemental probe passes 39 assertions; its old hard-coded pt/s position oracle was changed only to retained-position comparison for the new LPM contract. Aspect-fit geometry comparisons use a 1e-9 pt tolerance; the former exact-double checks differ by about 4e-13 pt while logical layout dimensions remain unchanged.

A synthetic 100,000-word paused measurement took about 0.35–0.59 s in 157 chunks on this host, with observed worst chunks about 3–6.3 ms. This is preparation evidence, not a display callback or sustained-performance claim. Full-document measurement never runs in a display callback. The below-2-ms frame goal and 60-minute memory/reading tests remain open.

The normal DebugLocal **scheme now passes all 20 native tests** through an unhosted app-linked integration target. It links the app's actual debug dylib and runtime paths; the test target has no second direct Core package dependency, which avoids duplicate Core type identities. This is a DebugLocal toolchain-specific runner configuration. The former hosted LaunchServices path still has the historical `childPID > 0` assertion; it is not relabelled a passing hosted launch. `scripts/test-app.sh` remains an optional direct execution cross-check using the same app-linked bundle. Neither path proves signed sandbox/iCloud behavior.

Actual launch evidence covers the concept sample in Ready and Paused, light/dark, at 1280×800, 1002×800 and 980×640. Exact pane geometry and aspect-ratio checks are automated. Native composite caches can omit text/layers or misrepresent appearance: direct editor and take-bar caches are retained to distinguish that limitation from missing text or a light bar. Activation/key-window attempts and actual outcomes are logged; these remain supporting evidence, not WindowServer screenshots or independent visual acceptance. Screen capture preflight is false; no permission was requested. The committed [concept board](docs/design/quiet-studio-concept.svg) remains proposed art.

Hardware/manual gates: physical low-speed/mixed-refresh/negative-origin rendering, fullscreen-call-app floating/click-through, optical reflection, real sleep/disconnect, VoiceOver/accessibility variants and macOS 14 runtime; signed iCloud delivery/offline conflicts/account/download on two Macs; sustained profiling. Each has procedures in [manual tests](docs/MANUAL_TEST_PLAN.md). No notarized/distributable release was produced.

[Architecture](docs/ARCHITECTURE.md) · [ADRs](docs/adr/README.md) · [design research](docs/design/README.md) · [implementation status](docs/IMPLEMENTATION_STATUS.md) · [Beans MVP](.beans/cueglass-aeqt--cueflow-v1-mvp.md)

MVP remains in-progress pending current-tip independent reviewer/tester passes. Owner/hardware/performance follow-ups remain open. Distribution later requires owner signing, hardened-runtime/archive review, notarization/stapling and a clean-machine Gatekeeper check; none is claimed here.
