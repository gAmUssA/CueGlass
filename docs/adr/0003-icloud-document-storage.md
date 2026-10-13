# 0003 — iCloud Drive storage of self-contained `.cueflow` documents

- **Status:** accepted
- **Date:** 2026-10-13
- **Related:** [0001](0001-native-document-and-immutable-take.md), [0002](0002-playback-snapshot-and-rendering.md), `CueFlow-Codex-Handoff.md` §5 and §8, requirement R04

## Context

Scripts must reach another Mac on the same iCloud account (R04), open and play offline, and never lose work on conflicts, account changes or unavailable containers. The development environment has no signing team, no iCloud container and no second Mac, so local builds must work without iCloud and must not fake cloud success.

Options considered: CloudKit database or a custom backend (rejected: out of scope); a live SQLite database in iCloud Drive (rejected: unsupported sync design); a custom save path, filesystem watcher or `NSMetadataQuery` library (rejected: competes with NSDocument's coordinated access); a document package with sidecar files (rejected: a single file is simpler to sync and validate).

## Decision

1. **Format.** `.cueflow` is one versioned JSON file (`formatVersion` 1): document ID, title, RTF payload, reading style and preferred speed. It is self-contained; no absolute path to an imported original is authoritative. Machine settings (output display, reflection, geometry) and playback state stay local.
2. **Codec guards.** `ScriptFileCodec` rejects oversize, malformed, non-finite and future-version input, clamps finite out-of-range values with a notice, and never rewrites a future-version file.
3. **NSDocument owns storage.** Autosave in place, Versions, coordinated reads/writes and the standard conflict workflow come from NSDocument. There is one save path. A future-version revert sets a save-blocked reason so autosave cannot overwrite newer data; Save a Copy stays available.
4. **Container and status.** The container comes only from `FileManager.url(forUbiquityContainerIdentifier:)`, off the main thread, from a build-configured identifier; never a hard-coded Mobile Documents path. Status is derived from ubiquity resource keys observed through `nonisolated` NSFilePresenter overrides that hop to the main actor. Labels never claim another Mac received the file. Account changes keep unsaved edits and offer a local copy; nothing is moved, duplicated or deleted automatically. Takes refuse to start on not-downloaded files.
5. **Configurations.** `DebugLocal` / `ReleaseLocal` need no iCloud signing and say "iCloud not configured in this build". `DebugICloud` / `ReleaseICloud` read owner-supplied team, bundle ID and container ID from a gitignored `Owner.xcconfig`. No credentials are committed.

## Consequences

- Easier: sync, versions and conflict handling reuse platform machinery; local development needs no Apple account.
- Harder: real behavior (conflict chooser on macOS 27, dataless-file download, container key expansion in `NSUbiquitousContainers`) can only be proven with owner credentials and two Macs.
- Later work must honor: no automatic conflict winner or RTF merge; no fabricated sync state; no second save path.

### Implementation status (2026-10-13)

- **Committed, developer-tested; independent acceptance pending:** items 1–5 are implemented through `d278e16ae6b91f2f7684a3a2649aa756924fa578` on `feat/cueflow-native`. Core codec/status helpers are committed; native integration is at `e92ffc5`, and storage/recovery hardening is at `d278e16`. Existing developer logs report 9 core tests and 11 direct AppKit tests passing, including local/unconfigured metadata, take isolation, future-version save protection and recovery to a different path. They do not prove real iCloud delivery or conflict recovery. See [implementation status](../IMPLEMENTATION_STATUS.md) and [MVP acceptance](../../.beans/cueglass-aeqt--cueflow-v1-mvp.md).
- **Actual storage UI:** explicit Save to iCloud uses container discovery and NSDocument save. Browse Versions is implemented via the SDK Swift spelling `browseVersions(_:)` in File/controls; Save a Copy remains available and cannot overwrite the protected future-version original. The optional direct Move to iCloud command is not implemented; a manual NSFileVersion resolver remains conditional on real conflict-UI findings. There is no automatic conflict winner or version deletion.
- **Owner configuration:** the committed per-config plist example uses an owner-edited literal NSUbiquitousContainers dictionary key, avoiding reliance on build-variable key expansion. Owner signing/configuration and actual signed plist/entitlement consistency remain unverified; see [iCloud setup](../ICLOUD_SETUP.md).
- **Unverified:** signed iCloud build, two-Mac delivery/offline conflicts, dataless-file and account-change behavior — [cueglass-ykl0](../../.beans/cueglass-ykl0--owner-icloud-setup-and-two-mac-verification.md). Accepted architecture does not close these acceptance gates.
