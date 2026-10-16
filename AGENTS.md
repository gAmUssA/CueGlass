# CueGlass Agent and Maintainer Guide

This file keeps build instructions and implementation context out of the user-facing README. Before changing application behavior, read the relevant architecture decision and check [current implementation evidence](docs/IMPLEMENTATION_STATUS.md) and the [manual test plan](docs/MANUAL_TEST_PLAN.md).

## Project map

- The product is CueGlass. The Xcode project, scheme, and Swift module retain the internal `CueFlow` name.
- `CueFlow/` contains the AppKit document, editor, playback, presentation, and storage layers.
- `Packages/CueFlowCore/` contains Foundation-only document, command, and timeline contracts.
- `CueFlowTests/` contains native AppKit integration tests; the core package has its own Swift Testing suite.
- `project.yml` is the XcodeGen project specification. The generated `CueFlow.xcodeproj` and shared scheme are committed; regenerating them is not needed for an ordinary build.
- `docs/adr/` records accepted architecture decisions. Add a new ADR when a change alters a documented contract rather than rewriting the earlier decision.
- `.beans/` tracks implementation and acceptance work. Keep the relevant Bean current, and do not mark the MVP milestone complete while its accepted verification gates remain open.

## Build and verify

The native app requires Apple's Xcode command-line toolchain, macOS SDK, and AppKit. The Foundation-only core can also be tested with Swift Package Manager. No Xcode GUI interaction is needed for these commands.

Build the local app and run it:

```sh
xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugLocal \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode build
open .build/Xcode/Build/Products/DebugLocal/CueFlow.app
```

Run core and native tests:

```sh
swift test --package-path Packages/CueFlowCore --scratch-path .build/core
TEST_RUNNER_CUEFLOW_EPHEMERAL=1 CUEFLOW_EPHEMERAL=1 xcodebuild \
  -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugLocal \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Xcode \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Other project checks:

```sh
scripts/test-app.sh
xcrun swift-format lint --strict --recursive CueFlow Packages/CueFlowCore/Sources \
  Packages/CueFlowCore/Tests CueFlowTests scripts/make-fixtures.swift \
  Packages/CueFlowCore/Package.swift
beans check --json
swift scripts/make-fixtures.swift
```

`scripts/test-app.sh` is an optional direct-runner cross-check. Fixture generation is useful when intentionally refreshing the synthetic files; do not run it as a routine test because it writes generated data into `.build/fixtures/` by default. Pass an explicit path only when you intend to write elsewhere.

## Implementation contracts

- `NSDocument` owns document lifecycle, coordinated saving, autosave, Versions, and change tracking. Authored RTF and source revisions remain separate from derived presentation styling.
- A playing take uses an immutable source snapshot. Reloading newer document content is explicit and paused; a failed reload retains the existing take. Rejected or unsupported disk revisions must not be overwritten silently, and Save a Copy remains the recovery path.
- Lines per minute is the saved pace contract. Font and line-height changes preserve the nominal pace and guide position. The effective pace may be limited by actual layout, with that limit shown to the user.
- Preview, selected-display output, and floating presentation share one logical viewport. At most one presentation surface is active. Surface changes preserve the guide anchor and prior play state when preparation succeeds.
- App-local keyboard commands must preserve normal editing in text fields. Do not add a global event monitor. Keep presentation timing and playback position out of document saves.
- Display callbacks must not read files, rebuild attributed strings, or dirty a document. Host-time timeline and TextKit 2 fragment layout are the playback/rendering sources of truth.
- `DebugLocal` and `ReleaseLocal` are local configurations without integrated iCloud entitlements. The source contains iCloud scaffolding, but the initial MVP makes no cross-Mac sync claim. Account setup, signing, notarization, cloud conflict/offline behavior, and two-Mac verification belong to the follow-up milestone.

For the full ownership and timing model, see [Architecture](docs/ARCHITECTURE.md) and [ADRs 0001–0011](docs/adr/README.md). For file limits, supported imports, interface requirements, and open manual gates, use the [implementation status](docs/IMPLEMENTATION_STATUS.md) and [manual test plan](docs/MANUAL_TEST_PLAN.md) as the current source of truth.

## CI and release notes

`.github/workflows/macos-release.yml` runs the core/native tests, strict Swift formatting, and a universal arm64/x86_64 release build on pull requests and branch pushes. Pushing a `vMAJOR.MINOR.PATCH` tag publishes a GitHub prerelease containing an unsigned, unnotarized ZIP, its checksum, and an explicit notice. Never describe that asset as signed or notarized, and do not add Gatekeeper bypass instructions. Signing and notarization require the later Apple Developer account milestone.
