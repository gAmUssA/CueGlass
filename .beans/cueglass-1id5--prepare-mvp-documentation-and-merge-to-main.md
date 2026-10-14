---
# cueglass-1id5
title: Prepare MVP documentation and merge to main
status: completed
type: task
priority: normal
created_at: 2026-10-14T15:11:01Z
updated_at: 2026-10-14T16:54:51Z
parent: cueglass-aeqt
---

Bring the current CueGlass MVP branch through the repo merge workflow, simplify README.md for app users, and move maintainer/agent implementation guidance into AGENTS.md.

- [x] Refresh branch against origin and inspect current release/CI state
- [x] Rewrite README as a concise human-facing product, setup, and release guide
- [x] Move detailed developer/build/test/implementation notes into AGENTS.md and link to existing docs
- [x] Verify docs and run required MVP/release checks
- [x] Create/update PR, resolve required reviews and CI, and merge to main
- [x] Verify main CI and clean up the merged branch

Do not include unrelated working-tree Bean edits.

## Review findings

- [x] Fix and regress timed-scrolling requests made during asynchronous measurement
- [x] Synchronize reading pace Undo/Redo with the model, session, and controls
- [x] Synchronize style Undo/Redo with active-take presentation state
- [x] Release the presentation claim when take preparation fails


## Current-head review follow-up

- [x] Confirm active-session style Undo/Redo regression is fixed and tested in 080a394
- [x] Fix generated-project merge attribute
- [x] Validate release tag against built app version
- [x] Give every connected display a unique picker key
- [x] Keep the floating grip visible when paused
- [x] Reject an explicitly malformed readingStyle field
- [x] Correct fixture generation path guidance
- [x] Use CueGlass terminology in import errors
- [x] Repair documentation links to maintainer commands and automated test evidence
- [x] Run core and native tests, strict formatting, Bean integrity, and diff checks

- [x] Remap the selected display after monitor topology changes and add a regression

- [x] Reject arithmetic overflow in Timed Scrolling before formatting pace diagnostics, with regressions
- [x] Record user-visible reliability improvements in the release notes


- [x] Fix newly surfaced review findings: show pending/canceled Timed Scrolling status, preserve editor selection on metadata refresh, and render Bean checklist correctly


- [x] Make fullscreen output noninteractive and synchronize the completed release Bean in the milestone tracker

## Summary of Changes

- Merged PR #3 (`16c81eb`) to `main` and removed the merged feature branch.
- Rewrote README for app users and moved build, test, and maintainer guidance into `AGENTS.md`.
- Verified main CI and published the unsigned, unnotarized `v0.1.1` prerelease with its ZIP, checksum, and notice.
- Preserved unrelated working-tree Bean edits.
