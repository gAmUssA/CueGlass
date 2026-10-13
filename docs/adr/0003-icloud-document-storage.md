# 0003 — iCloud Drive storage of self-contained `.cueflow` documents

- **Status:** accepted
- **Date:** 2026-10-13
- **Related:** [0001](README.md) (pending), [0002](0002-playback-snapshot-and-rendering.md), `CueFlow-Codex-Handoff.md` §5 and §8, requirement R04

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

- **Implemented and tested:** format, codec guards, `CloudStatus` mapping and display matching in `Packages/CueFlowCore` at `fdbffc2`.
- **Implemented, not accepted:** document save-block, presenter overrides, storage actor, account-change banner and local/iCloud configurations exist in the primary developer's uncommitted native work.
- **Recommended, not implemented:** "Move to iCloud…" via `moveDocumentToUbiquityContainer(_:)` and a conflict banner offering "Browse Versions…" via `browseDocumentVersions(_:)` were not observed in the native source; a manual `NSFileVersion` resolver remains conditional on hardware findings.
- **Unverified:** everything requiring a signed iCloud build and a second Mac — bean `cueglass-ykl0`.
