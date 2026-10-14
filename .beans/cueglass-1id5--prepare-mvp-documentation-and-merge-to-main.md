---
# cueglass-1id5
title: Prepare MVP documentation and merge to main
status: in-progress
type: task
priority: normal
created_at: 2026-10-14T15:11:01Z
updated_at: 2026-10-14T15:36:34Z
parent: cueglass-aeqt
---

Bring the current CueGlass MVP branch through the repo merge workflow, simplify README.md for app users, and move maintainer/agent implementation guidance into AGENTS.md.\n\n- [x] Refresh branch against origin and inspect current release/CI state\n- [x] Rewrite README as a concise human-facing product, setup, and release guide\n- [x] Move detailed developer/build/test/implementation notes into AGENTS.md and link to existing docs\n- [x] Verify docs and run required MVP/release checks\n- [ ] Create/update PR, resolve required reviews and CI, and merge to main\n- [ ] Verify main CI and clean up the merged branch\n\nDo not include unrelated working-tree Bean edits.

## Review findings\n\n- [x] Fix and regress timed-scrolling requests made during asynchronous measurement\n- [x] Synchronize reading pace Undo/Redo with the model, session, and controls\n- [x] Synchronize style Undo/Redo with active-take presentation state\n- [x] Release the presentation claim when take preparation fails


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
