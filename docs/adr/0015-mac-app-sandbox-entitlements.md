# Title

Mac App Sandbox entitlements for the App Store build

# Status

proposed

# Date

2026-11-03

# Context

ADR 0014 distributes signed CueGlass builds through the Mac App Store, and Mac App Store apps must be sandboxed (Apple requirement; ADR 0014 itself does not mention the sandbox). Bean `cueglass-sx4d` ran a spike on 2026-11-03 against `main`. The existing `DebugLocal` and `ReleaseLocal` configurations already sign with `CueFlow/Resources/CueFlow-Local.entitlements`, so the local build is sandboxed today; the spike needed no experimental change (the experiment diff is empty).

Observed: `codesign -d --entitlements -` on the `DebugLocal` app shows `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `device.audio-input` (plus the debug-only `get-task-allow`). Launched with `open -a CueGlass.app a.txt rich.rtf b.rtf` (one `.txt`, two `.rtf`), the app ran inside the existing container `~/Library/Containers/com.example.cueflow` (created by earlier sandboxed runs, birth time Oct 13 2026) and opened the imports as untitled documents. `log show --predicate 'process == "CueGlass" || process == "sandboxd" || subsystem == "com.apple.sandbox.reporting"' --last 5m` showed no sandbox denial or violation lines; the only lines containing the word "deny" are two benign CoreAudio messages ("application is not in client deny list").

Observed from source: no `AVCaptureDevice` or other camera capture, no `URLSession` or `Network` use, no `Process` in the CueFlow target (`Experiments/VoiceFollow/.../FixtureMaker.swift` uses it for `/usr/bin/say` but is not compiled into the app), AppleScript, global event monitor, event tap, status item or login item. File access is `NSDocument` (user-selected panels and Finder opens), one `NSSavePanel` for iCloud saves, and, in the CueFlow target, `FileManager` calls confined to the iCloud container in `DocumentStorageService` (tests, `scripts/make-fixtures.swift` and `Experiments/` also use `FileManager` but are not in the app). `NSWorkspace.shared.open` opens only the `x-apple.systempreferences:` microphone privacy pane. Speech uses `SpeechTranscriber` and, for English commands, `DictationTranscriber` in the same analyzer; `install` requests assets for both modules through `AssetInventory.assetInstallationRequest` and `downloadAndInstall()` (`SpeechVoiceSource.swift:127-144`), with no direct network code. The source does not show which process transfers the bytes.

Not run: the headless session could not capture the screen or deliver synthetic UI input, so panel and menu rows were not driven. Not run: open panel, Finder double-click of `.cueflow`, Save, autosave and Versions, Save a Copy, the microphone permission prompt, the on-device speech model download, and Follow Voice end to end.

Documented (Apple's AssetInventory page): speech assets are models downloaded from Apple's servers and managed by the system, and the app does not work with them directly.

Inferred from Apple documentation, not observed: `SpeechTranscriber` and `DictationTranscriber` do not use the `SFSpeechRecognizer` server path, so `NSSpeechRecognitionUsageDescription` is likely not needed; the system asset download needs no `network.client` entitlement from the app. Both must be confirmed on hardware.

Info.plist facts (observed): `NSMicrophoneUsageDescription` present; no `NSCameraUsageDescription` (Camera Dock never opens the camera, per the implementation status); no `NSSpeechRecognitionUsageDescription`; no `LSApplicationCategoryType`; no `ITSAppUsesNonExemptEncryption`; `LSMinimumSystemVersion` 14.0; bundle identifier is still `com.example.cueflow`. The ad-hoc signature carries no hardened runtime flag (`flags=0x2(adhoc)`).

# Decision

The App Store configuration ships exactly these entitlements:

- `com.apple.security.app-sandbox` = true. Required for the Mac App Store.
- `com.apple.security.files.user-selected.read-write` = true. Open and save panels, Finder opens, Save a Copy and autosave next to user-chosen documents.
- `com.apple.security.device.audio-input` = true. Follow Voice captures the microphone with `AVAudioEngine`.

Deliberately not requested: `network.client` (no network code; add only if hardware validation shows the speech model download fails), camera (`device.camera`; no capture), `files.bookmarks.app-scope` (no stored file references), downloads or other folder entitlements, and any temporary-exception entitlement. The iCloud entitlements (`icloud-container-identifiers`, `ubiquity-container-identifiers`, `icloud-services` = CloudDocuments, already in `CueFlow-iCloud.entitlements`) stay out of the first App Store build. `AGENTS.md` makes no cross-Mac sync claim for the MVP and leaves cloud conflict and offline behavior and two-Mac verification to a follow-up milestone. ADR 0014 defers signing and App Store submission to the Apple Developer account milestone and does not defer cloud sync. ADR 0003 remains the accepted iCloud Drive storage design. Adding the container entitlements later needs a container identifier owned by the Team ID.

Info.plist and signing items for the future configuration: add `LSApplicationCategoryType` (a productivity category such as `public.app-category.productivity`), `ITSAppUsesNonExemptEncryption` = NO (inferred: the app uses no custom or non-exempt encryption), enable the hardened runtime, replace `com.example.cueflow` with the owner's bundle identifier, and drop `get-task-allow` from the distribution signature. Keep the microphone string, and omit the camera and speech strings unless hardware validation shows macOS prompting for them.

Wiring these into `project.yml` and signing is bean `cueglass-pili`, not this decision's change.

# Consequences

The existing Local entitlements already match the proposed set, so the sandbox is unlikely to force a feature cut. No feature is known to be impossible under the sandbox; that claim rests on source inspection and one launch, not on exercising the rows above.

Must be verified on hardware before this record is accepted, with an ad-hoc or development-signed sandboxed build:

1. Open `.txt`, `.rtf` and `.cueflow` through the open panel and Finder double-click, and save, autosave, Versions and Save a Copy, with no sandbox denials in Console.
2. The microphone permission prompt and Follow Voice end to end, including the on-device speech model download on a Mac without the model, and whether it needs `network.client`.
3. Whether macOS shows a speech recognition prompt (decides `NSSpeechRecognitionUsageDescription`).
4. The Privacy & Security microphone link from `openMicrophoneSettings`.
5. A distribution-signed archive passes App Store Connect validation (category, encryption key, hardened runtime, bundle identifier).

Later work must not add a network, camera, folder or temporary-exception entitlement without amending this record or superseding it.
