# Title

Provisional App Store signing configuration and fastlane build

# Status

proposed

# Date

2026-11-03

# Context

ADR 0014 distributes signed CueGlass builds through the Mac App Store and leaves signing to the Apple Developer account milestone. ADR 0015 (proposed) lists the entitlements for that build and records an open question: whether the sandboxed, hardened-runtime build also needs `com.apple.security.device.microphone`. Beans `cueglass-pili` (signing, build-settings half) and `cueglass-h2tz` (fastlane) cover this change.

Owner decisions for this change (stated by the owner in the session): Apple Team ID `3ZMBGR95M8`; bundle identifier `io.gamov.cueglass`; the source stays free under MIT while the App Store build is sold at 3.99 USD; GitHub publishes no binaries (ADR 0014); fastlane automates the App Store build.

Observed in this change: `xcodegen` was already installed (version 2.46.0) and regenerated `CueFlow.xcodeproj` with no diff before the edit. An unsigned `ReleaseAppStore` build (`CODE_SIGNING_ALLOWED=NO`) succeeded, and the built app's Info.plist reported `CFBundleIdentifier` `io.gamov.cueglass`, `LSApplicationCategoryType` `public.app-category.productivity`, `ITSAppUsesNonExemptEncryption` false and the existing `NSMicrophoneUsageDescription`. An unsigned build embeds no entitlements, so the entitlements check reads the file named by `CODE_SIGN_ENTITLEMENTS`, not the built app.

# Decision

Provisional: the entitlements file carries the proposed ADR 0015 entitlement set and changes if hardware validation changes that set. The other items below do not depend on that set.

- Configuration: a `ReleaseAppStore` configuration (release-based) in `project.yml`, with shared values in `Configuration/AppStore.xcconfig`: bundle identifier `io.gamov.cueglass`, `DEVELOPMENT_TEAM` `3ZMBGR95M8`, `ENABLE_HARDENED_RUNTIME` YES, automatic signing style with the `Apple Development` identity for the archive, and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` NO. The test target uses `io.gamov.cueglass.tests` in this configuration. `DebugLocal` and `ReleaseLocal` keep ad-hoc signing (`CODE_SIGN_IDENTITY = -`) and the `com.example.cueflow` identifier. The iCloud configurations are unchanged: `ICloud.xcconfig` sets no signing identity, the project signing style is Automatic, and their identifier stays `com.example.cueflow`.
- Entitlements: `CueFlow/Resources/CueFlow-AppStore.entitlements` holds exactly `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write` and `com.apple.security.device.audio-input`, with no `get-task-allow`. `com.apple.security.device.microphone` is not added (ADR 0015 open question).
- Info.plist (shared by all non-iCloud configurations): `LSApplicationCategoryType` `public.app-category.productivity`, chosen because the ADR 0015 suggestion fits a script-reading tool for presenters and no more specific public category was verified; `ITSAppUsesNonExemptEncryption` NO, inferred because the app has no non-exempt encryption (ADR 0015 decision text; Apple's "Complying with Encryption Export Regulations" page, opened by the reviewer, says to set NO when an app uses no encryption or only exempt encryption). Separately, observed: no `URLSession` or `Network` use under `CueFlow/`. That is not the export-compliance test, and a later network change must re-check the key against the encryption criterion. The existing `NSMicrophoneUsageDescription` covers microphone use. No `NSSpeechRecognitionUsageDescription` is added, per the ADR 0015 inference that no `SFSpeechRecognizer` API is called (re-checked in this change: no `SFSpeechRecognizer` or `NSSpeechRecognition` string appears under `CueFlow/`).
- Identity choice (inferred, not tested): the `Apple Development` identity at archive time with a distribution re-sign at export matches the `mac build` lane, which passes `-configuration ReleaseAppStore` to the archive; the shared scheme's Product > Archive action stays `ReleaseLocal` and is not changed. The explicit distribution identity, provisioning profile and installer certificate are owner-only and not set.
- fastlane (new dependency, stated before the edit): `fastlane` 2.241.2 via Bundler, pinned in `Gemfile` with `Gemfile.lock` committed and a Dependabot `bundler` entry in `.github/dependabot.yml`. Rejected alternative: `xcodebuild` plus `notarytool` scripts, because `deliver` handles metadata and screenshots (bean `cueglass-h2tz`). Lanes in `fastlane/Fastfile`: `mac build` (gym export of `ReleaseAppStore`), `mac beta` (TestFlight upload), `mac release` (`deliver` submit; metadata and screenshots skipped until they exist). `match` is not used: automatic signing with the App Store Connect API key replaces it, and that choice is revisitable by the owner.
- Secrets: the lanes read only `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID` and `APP_STORE_CONNECT_API_KEY_PATH` from the environment; `.env.example` lists placeholders. No certificate, profile, password or key is committed. The Team ID is an identifier shown in the Apple Developer account, not a secret, so it is committed.
- Check: `scripts/test-app-store-config.sh` builds `ReleaseAppStore` unsigned and asserts bundle id, hardened runtime, exactly the three entitlement keys and the Info.plist keys, plus negative entitlement cases. It is not wired into the workflow; bean `cueglass-nnff` tracks a CI step.

# Consequences

Observed: the unsigned build and `scripts/test-app-store-config.sh` pass, and the script fails when the bundle id, the entitlements file or an Info.plist key is reverted. `bundle exec fastlane lanes` lists `build`, `beta` and `release`; `build` stops with a message naming the missing environment variables.

NOT RUN, owner-only: any signed build, code-signing identity or provisioning profile creation, App Store Connect validation, TestFlight upload, `deliver` submission and any lane against real credentials. A separate notarization is the Developer ID (direct distribution) path; it is not a step of `mac build` or `mac release`, and Apple's notarization page says Mac App Store software needs no separate notarization (the reviewer opened that page; not re-run here). No signed, notarized or App Store-validated build was produced. An unsigned build is never described as signed or notarized.

Owner-only next steps: run the ADR 0015 hardware rows and settle `device.microphone`; create the App Store Connect API key and set the three environment variables; run `bundle exec fastlane mac build`, then `beta`; supply listing metadata and screenshots, then drop the `skip_metadata` and `skip_screenshots` flags from the `release` lane. Installing Ruby or fastlane machine-wide needs the owner's yes; this change installed fastlane only into the gitignored `vendor/bundle`.

Later work must not add network, camera, folder or temporary-exception entitlements without amending ADR 0015 or superseding it, and must not reintroduce GitHub binaries (ADR 0014).
