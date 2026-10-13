# CueFlow (provisional)

Native macOS teleprompter in the CueGlass repository. macOS 14+, AppKit documents/windows and TextKit 2 rendering, SwiftUI controls, Foundation-only playback core. No external runtime dependencies. The working name has not been cleared for branding or distribution.

## Build and run locally

Validated toolchain: Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0 (26A428), arm64. The committed project and shared CueFlow scheme open directly in Xcode. Select DebugLocal and Run. No Apple development team or iCloud entitlement is needed for local ad hoc signing.

```sh
xcodebuild -project CueFlow.xcodeproj -scheme CueFlow \
  -configuration DebugLocal -destination 'platform=macOS' \
  -derivedDataPath .build/Xcode build
open .build/Xcode/Build/Products/DebugLocal/CueFlow.app
```

Quit with Command-Q. Build artifacts, generated fixtures and owner configuration are ignored. `project.yml` is the generation source; the real `.xcodeproj` and shared scheme are committed as expressly required. Regenerate with installed XcodeGen 2.46.0 (`xcodegen generate`). No generation step is required to build the committed project.

## Use

- File → New/Open, or drop a TXT/RTF/native file onto the editor. Imports create a new unsaved native document; the original is untouched. Save creates a self-contained `.cueflow` JSON file containing authored RTF and reading preferences.
- Edit with native selection, clipboard, Undo/Redo, Bold/Italic, and Fonts. Choose Normalized typography to retain emphasis with a uniform reading font; Preserve Source keeps relative source font sizes and colors. Presentation changes never flatten the source.
- Play/Pause, Restart, and Stop Take control the one active take. Stop unlocks editing. Speed uses layout points/second, with slider, number field and stepper. Typography, width, spacing and guide changes pause and restore the text under the guide.
- Space toggles play/pause and Up/Down adjust speed by 5 when focus is in the presentation area. Editor and control focus keep normal editing. Menu commands use Option-Command-P, Option-Command-Up/Down, Option-Command-O and Option-Command-R.
- Choose a named display and Show Output. The selected display owns logical layout; preview scales the same layout. Choosing the operator screen requires confirmation. Escape or Stop Output exits. Disconnect and sleep pause at the last presented position. Hiding the operator window does not make it authoritative while output is active.
- Horizontal and Vertical reflect independently. Show as output applies the same reflections to preview. Calibration replaces the editable script with an asymmetric fixture and can be undone; stop the take first.
- Save On This Mac uses normal document panels. Save to iCloud discovers the entitled container and uses NSDocument's save path; see [iCloud setup](docs/ICLOUD_SETUP.md). Local mode honestly says iCloud is not configured. Uploaded to iCloud never claims another Mac received the file.
- A new document revision cannot replace an active snapshot. Pause and Load Latest explicitly to use it. Changed text resets position; identical text carries the reading anchor into new layout. Versions and Save a Copy preserve recovery options.

## Import limits and supported subset

TXT: 8 MiB; RTF: 16 MiB; native JSON: 32 MiB, with a 16 MiB RTF payload. Sizes are checked before URL reads and after decoding. No truncation. TXT supports strict UTF-8 and BOM UTF-8/UTF-16LE/BE. Ambiguous input offers UTF-16LE/BE, Windows-1252, Mac Roman or Windows-1251 with a confirmation preview. CRLF/CR become LF; blank paragraphs and Unicode remain.

RTF is read with the explicit native RTF API. Text, bold/italic, supported fonts/colors and basic paragraph formatting are retained. Attachments/table runs are detected and disclosed before import; they stay in source but are removed/simplified in presentation. Links remain in source and are disabled in presentation. This is not complete word-processor fidelity. RTFD, DOCX and PDF are unsupported. Malformed/future native files do not replace good content. A future-version revert blocks saves to protect newer disk bytes; Save a Copy remains available.

## Automated checks and actual results

Run from the repository root:

```sh
swift test --package-path Packages/CueFlowCore --scratch-path .build/core
scripts/test-app.sh
xcrun swift-format lint --strict --recursive CueFlow Packages/CueFlowCore/Sources \
  Packages/CueFlowCore/Tests CueFlowTests scripts/make-fixtures.swift Packages/CueFlowCore/Package.swift
swift scripts/make-fixtures.swift
```

Executed on the toolchain above: core Swift Testing tests pass (9 tests, including 3 velocity cases); hosted AppKit Swift Testing bundle passes (11 tests); local app/build-for-testing compile with Swift warnings as errors. Integration tests exercise actual RTF decode, import originals/mtime, native round trips, malformed and future-version refusal, save protection, derived styling/anchor restoration, immutable takes/stalls, link teardown, operator rendering and editor key events, output-loss retention, undo, local metadata and long-script layout. They generate `.build/operator-window.png` for inspection.

`xcodebuild … test` was also attempted, both unsigned and ad hoc signed. Xcode's LaunchServices test launcher aborted with `IDELaunchServicesLauncher.m:445`, `childPID > 0` (exit 134). This is **not a passing scheme test**. `scripts/test-app.sh` builds the same hosted test bundle, then invokes the installed `xctest` runner directly with its framework/dylib paths. Swift Testing's final nonzero test count is the result; the preceding XCTest “0 tests” line is not the verdict. This bypass does not prove sandbox or iCloud behavior.

No physical-output smoothness, mixed-refresh behavior, 60-minute profiling, optical reflection or real two-Mac synchronization has been claimed. The platform-bound portions exempt from automated proof are the real CADisplayLink cadence, physical screen topology/optics, signed sandbox panels and iCloud account/conflict delivery. Each has a pass/fail procedure in [manual tests](docs/MANUAL_TEST_PLAN.md). See [implementation status](docs/IMPLEMENTATION_STATUS.md) for requirement coverage.

## Design and setup

[Architecture](docs/ARCHITECTURE.md) · [ADR](docs/adr/0001-native-document-and-immutable-take.md) · [iCloud](docs/ICLOUD_SETUP.md) · [manual validation](docs/MANUAL_TEST_PLAN.md)

No notarized or distributable release was produced. Distribution requires the owner's signing identity, hardened runtime/archive review, Developer ID signing and notarization with `notarytool`, stapling, and a clean-machine Gatekeeper check. Do not distribute this private development branch as a verified release.
