# Title

Mac App Sandbox entitlements for the App Store build

# Status

proposed

# Date

2026-11-03

# Context

ADR 0014 sells signed CueGlass builds on the Mac App Store, which requires the App Sandbox. Bean `cueglass-sx4d` ran a spike on 2026-11-03 against `main`. The existing `DebugLocal` and `ReleaseLocal` configurations already sign with `CueFlow/Resources/CueFlow-Local.entitlements`, so the local build is sandboxed today; the spike needed no experimental change (the attached experiment diff is empty).

Observed: `codesign -d --entitlements -` on the `DebugLocal` app shows `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `device.audio-input` (plus the debug-only `get-task-allow`). Launched through `open -a` with two `.txt` files and two `.rtf` files, the app created `~/Library/Containers/com.example.cueflow` and opened each import as an untitled document. `log show --predicate 'process == "CueGlass" || process == "sandboxd" || subsystem == "com.apple.sandbox.reporting"' --last 5m` showed no deny or violation lines.

Observed from source: no `AVCaptureDevice` or other camera capture, no `URLSession` or `Network` use, no `Process`, AppleScript, global event monitor, event tap, status item or login item. File access is `NSDocument` (user-selected panels and Finder opens), one `NSSavePanel` for iCloud saves, and `FileManager` calls confined to the iCloud container in `DocumentStorageService`. `NSWorkspace.shared.open` opens only the `x-apple.systempreferences:` microphone privacy pane. Speech uses `SpeechTranscriber` and `AssetInventory` with no direct network code; the model download is performed through the system asset service.

Not run: the headless session could not capture the screen or deliver synthetic UI input, so panel and menu rows were not driven. Not run: open panel, Finder double-click of `.cueflow`, Save, autosave and Versions, Save a Copy, the microphone permission prompt, the on-device speech model download, and Follow Voice end to end.

Inferred from Apple documentation, not observed: `SpeechTranscriber` does not use the `SFSpeechRecognizer` server path, so `NSSpeechRecognitionUsageDescription` is likely not needed; the system asset download needs no `network.client` entitlement from the app. Both must be confirmed on hardware.

Info.plist facts (observed): `NSMicrophoneUsageDescription` present; no `NSCameraUsageDescription` (Camera Dock never opens the camera, per the implementation status); no `NSSpeechRecognitionUsageDescription`; no `LSApplicationCategoryType`; no `ITSAppUsesNonExemptEncryption`; `LSMinimumSystemVersion` 14.0; bundle identifier is still `com.example.cueflow`. The ad-hoc signature carries no hardened runtime flag (`flags=0x2(adhoc)`).

# Decision

The App Store configuration ships exactly these entitlements:

- `com.apple.security.app-sandbox` = true. Required for the Mac App Store.
- `com.apple.security.files.user-selected.read-write` = true. Open and save panels, Finder opens, Save a Copy and autosave next to user-chosen documents.
- `com.apple.security.device.audio-input` = true. Follow Voice captures the microphone with `AVAudioEngine`.

Deliberately not requested: `network.client` (no network code; add only if hardware validation shows the speech model download fails), camera (`device.camera`; no capture), `files.bookmarks.app-scope` (no stored file references), downloads or other folder entitlements, and any temporary-exception entitlement. The iCloud entitlements (`icloud-container-identifiers`, `ubiquity-container-identifiers`, `icloud-services` = CloudDocuments, already in `CueFlow-iCloud.entitlements`) stay out of the first App Store build, since ADR 0014 and `AGENTS.md` defer cloud sync to a later milestone; adding them then needs a container identifier owned by the Team ID.

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
