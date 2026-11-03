---
# cueglass-pili
title: Apple Developer account integration, signing, and notarization
status: in-progress
type: task
priority: high
created_at: 2026-10-14T13:34:22Z
updated_at: 2026-11-03T18:32:03Z
parent: cueglass-gzi5
blocked_by:
    - cueglass-aeqt
    - cueglass-sx4d
---

Integrate the owner’s Apple Developer account and prepare a distributable signed CueGlass build.

Acceptance:
- Record Developer Team ID 3ZMBGR95M8 and bundle identifier io.gamov.cueglass in the committed App Store configuration (Configuration/AppStore.xcconfig; the Team ID is an identifier, not a secret). Owner-only secrets are the App Store Connect API key, certificates and provisioning profiles.
- Configure signing, entitlements, and release build settings without committing secrets.
- Sign the release with the intended distribution identity.
- Developer ID direct-download path only (not a step of the Mac App Store path, ADR 0016): submit for notarization, staple the ticket, and verify Gatekeeper assessment on a clean machine/install.
- Document reproducible build commands and results (and notarization commands if the Developer ID path is pursued).

## Competitor research link (2026-11-03)

Signed and notarized distribution is the largest install-trust gap versus CueNotch, Notchie, NotchPrompter and Notch. Tracked in epic cueglass-2ur9.

## Operator decision (2026-11-03)

Publish on the Mac App Store at 3.99 USD to cover the Apple Developer fee (also needed for notarization of the direct download). The source stays free and MIT. Needs the sandbox spike first, see the epic.

## Update (2026-11-03)

The owner already has an Apple Developer account, so no sign-up step is needed. The v0.3.0 prerelease notes are marked superseded; the release is kept for now.

## Sandbox findings (2026-11-03, from cueglass-sx4d, ADR 0015 proposed)

Proposed entitlements for the App Store configuration (not final): com.apple.security.app-sandbox, com.apple.security.files.user-selected.read-write, com.apple.security.device.audio-input. Open question: Apple documents audio-input as the Hardened Runtime key and com.apple.security.device.microphone as the App Sandbox Hardware Audio Input key; the sandboxed build may also need device.microphone, to be settled on hardware with a sandboxed build that has the Hardened Runtime enabled (a build without it does not settle it). Not requested: network.client, device.camera, bookmarks, folder access. iCloud container entitlements stay out of the first build.

Also needed: LSApplicationCategoryType, ITSAppUsesNonExemptEncryption=NO (inferred), hardened runtime, real bundle identifier (com.example.cueflow in DebugLocal and ReleaseLocal; ReleaseAppStore is io.gamov.cueglass, see the progress note), no get-task-allow in the distribution signature.

Open hardware rows: open/save/autosave/Versions/Save a Copy, Finder double-click of .cueflow, microphone prompt, speech model download (network.client?), Follow Voice, whether a speech recognition prompt appears.

## Progress (2026-11-03, build-settings half)

Done in ADR 0016 (proposed): ReleaseAppStore configuration with bundle identifier io.gamov.cueglass, Team ID 3ZMBGR95M8, hardened runtime, the three provisional ADR 0015 entitlements without get-task-allow, LSApplicationCategoryType and ITSAppUsesNonExemptEncryption. Remaining: the distribution signing identity and profile, and App Store Connect validation (NOT RUN, owner-only). A separate notarization is the Developer ID path and is not a step of mac build or mac release; no signed, notarized or App Store-validated build was produced. Follow-up for a CI step: cueglass-nnff.
