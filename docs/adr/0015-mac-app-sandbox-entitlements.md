# Title

Mac App Sandbox entitlements for the App Store build

# Status

proposed

# Date

2026-11-03

# Context

ADR 0014 distributes signed CueGlass builds through the Mac App Store, and Mac App Store apps must be sandboxed (documented: the Xcode page "Configuring the macOS App Sandbox" calls `com.apple.security.app-sandbox` an App Store requirement for any app submitted to the Mac App Store; ADR 0014 itself does not mention the sandbox). Bean `cueglass-sx4d` ran a spike on 2026-11-03 against `main`. The existing `DebugLocal` and `ReleaseLocal` configurations already sign with `CueFlow/Resources/CueFlow-Local.entitlements`, so the local build is sandboxed today; the spike needed no experimental change (the experiment diff is empty).

Observed during the spike (not re-run in the later wording fixes): `codesign -d --entitlements -` on the `DebugLocal` app shows `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `device.audio-input` (plus the debug-only `get-task-allow`). Launched with `open -a CueGlass.app a.txt rich.rtf b.rtf` (one `.txt`, two `.rtf`), the app ran inside the existing container `~/Library/Containers/com.example.cueflow` (created by earlier sandboxed runs, birth time Oct 13 2026) and opened the imports as untitled documents. `log show --predicate 'process == "CueGlass" || process == "sandboxd" || subsystem == "com.apple.sandbox.reporting"' --last 5m` showed no sandbox denial or violation lines; the only lines containing the word "deny" are two benign CoreAudio messages ("application is not in client deny list").

Observed from source: no `AVCaptureDevice` or other camera capture, no `URLSession` or `Network` use, no `Process` in the CueFlow target (`Experiments/VoiceFollow/.../FixtureMaker.swift` uses it for `/usr/bin/say` but is not compiled into the app), AppleScript, global event monitor, event tap, status item or login item. File access is `NSDocument` (user-selected panels and Finder opens), one `NSSavePanel` for iCloud saves, and, in the CueFlow target, `FileManager` calls confined to the iCloud container in `DocumentStorageService` (tests, `scripts/make-fixtures.swift` and `Experiments/` also use `FileManager` but are not in the app). `NSWorkspace.shared.open` opens only the `x-apple.systempreferences:` microphone privacy pane. Speech uses `SpeechTranscriber` and, for English commands, `DictationTranscriber` in the same analyzer; `install` requests assets for both modules through `AssetInventory.assetInstallationRequest` and `downloadAndInstall()` (`SpeechVoiceSource.swift:127-144`), with no direct network code. The source does not show which process transfers the bytes.

Not run: the headless session could not capture the screen or deliver synthetic UI input, so panel and menu rows were not driven. Not run: open panel, Finder double-click of `.cueflow`, Save, autosave and Versions, Save a Copy, the microphone permission prompt, the on-device speech model download, and Follow Voice end to end.

Documented (Apple's AssetInventory page): speech assets are models downloaded from Apple's servers and managed by the system, and the app does not work with them directly.

Documented (Apple's "Asking Permission to Use Speech Recognition" page): a note says "This process only applies to speech recognition using `SFSpeechRecognizer`", and that `SpeechAnalyzer` transcriber modules do not send audio data of the user's voice to Apple's servers. The same page says the app crashes if `NSSpeechRecognitionUsageDescription` is missing when it calls `SFSpeechRecognizer.requestAuthorization(_:)`. Inferred, not observed: because CueFlow calls no `SFSpeechRecognizer` API, `NSSpeechRecognitionUsageDescription` is likely not needed; the system-managed asset download needs no `network.client` entitlement from the app (Apple does not document that exemption). Both must be confirmed on hardware.

Info.plist facts (observed): `NSMicrophoneUsageDescription` present; no `NSCameraUsageDescription` (Camera Dock never opens the camera, per the implementation status); no `NSSpeechRecognitionUsageDescription`; no `LSApplicationCategoryType`; no `ITSAppUsesNonExemptEncryption`; `LSMinimumSystemVersion` 14.0; bundle identifier is still `com.example.cueflow`. The ad-hoc signature carries no hardened runtime flag (`flags=0x2(adhoc)`).

# Decision

The App Store configuration ships exactly these entitlements:

- `com.apple.security.app-sandbox` = true. Required for the Mac App Store.
- `com.apple.security.files.user-selected.read-write` = true. Open and save panels, Finder opens, Save a Copy and autosave next to user-chosen documents.
- `com.apple.security.device.audio-input` = true. Follow Voice captures the microphone with `AVAudioEngine`. Documented: Apple's "Audio Input Entitlement" page for this key says to enable the Hardened Runtime capability and select Audio Input under Resource Access, so it is the Hardened Runtime key. Apple's `com.apple.security.device.microphone` page says to enable the App Sandbox capability and select Audio Input under Hardware, and "Configuring the macOS App Sandbox" points its Hardware > Audio Input row at that key, so `device.microphone` is the App Sandbox key. The set keeps `device.audio-input` because the local build ships it and the "Configuring the hardened runtime" page lists it for the Resource Access > Audio Input row; whether the App Store build needs the hardened runtime is inferred (see the signing paragraph below).

Open question: the sandboxed App Store build may additionally need `com.apple.security.device.microphone`. The local build ships `device.audio-input` only and has no hardened runtime, so sandboxed microphone capture with the Hardened Runtime capability enabled is not yet shown; closing the question needs a build that is both sandboxed and hardened-runtime (hardware row 2). This record adds no key until hardware settles it.

Deliberately not requested: `network.client` (no network code; add only if hardware validation shows the speech model download fails), camera (`device.camera`; no capture), `files.bookmarks.app-scope` (no stored file references), downloads or other folder entitlements, and any temporary-exception entitlement. The iCloud entitlements (`icloud-container-identifiers`, `ubiquity-container-identifiers`, `icloud-services` = CloudDocuments, already in `CueFlow-iCloud.entitlements`) stay out of the first App Store build. `AGENTS.md` makes no cross-Mac sync claim for the MVP and leaves cloud conflict and offline behavior and two-Mac verification to a follow-up milestone. ADR 0014 defers signing and App Store submission to the Apple Developer account milestone and does not defer cloud sync. ADR 0003 remains the accepted iCloud Drive storage design. Adding the container entitlements later needs a container identifier owned by the Team ID.

Info.plist and signing items for the future configuration (the category value and `ITSAppUsesNonExemptEncryption` are inferred; those two pages were not opened for this record. Documented, from Apple's "Hardened Runtime" page: "To upload a macOS app to be notarized, you must enable the Hardened Runtime capability." Whether the App Store build needs the capability is inferred; the page was opened and does not mention the Mac App Store): add `LSApplicationCategoryType` (a productivity category such as `public.app-category.productivity`), `ITSAppUsesNonExemptEncryption` = NO (inferred: the app uses no custom or non-exempt encryption), enable the hardened runtime, replace `com.example.cueflow` with the owner's bundle identifier, and drop `get-task-allow` from the distribution signature. Keep the microphone string, and omit the camera and speech strings unless hardware validation shows macOS prompting for them.

Wiring these into `project.yml` and signing is bean `cueglass-pili`, not this decision's change.

# Consequences

The existing Local entitlements already match the proposed set, so the sandbox is unlikely to force a feature cut. No feature is known to be impossible under the sandbox; that claim rests on source inspection and one launch, not on exercising the rows above.

Must be verified on hardware before this record is accepted, with an ad-hoc or development-signed sandboxed build:

1. Open `.txt`, `.rtf` and `.cueflow` through the open panel and Finder double-click, and save, autosave, Versions and Save a Copy, with no sandbox denials in Console.
2. The microphone permission prompt and Follow Voice end to end, including the on-device speech model download on a Mac without the model, and whether it needs `network.client`. The confirmation build is ad-hoc or development-signed, sandboxed, and has the Hardened Runtime capability enabled. The first pass uses `device.audio-input` without `device.microphone`. A pass on a build without the hardened runtime, such as today's `DebugLocal` build, does not close the question. If the hardened-runtime build is denied the microphone, add `com.apple.security.device.microphone` and retest. Record the working key or keys before this record is accepted.
3. Whether macOS shows a speech recognition prompt (decides `NSSpeechRecognitionUsageDescription`).
4. The Privacy & Security microphone link from `openMicrophoneSettings`.
5. A distribution-signed archive passes App Store Connect validation (category, encryption key, hardened runtime, bundle identifier).

Later work must not add a network, camera, folder or temporary-exception entitlement without amending this record or superseding it.
