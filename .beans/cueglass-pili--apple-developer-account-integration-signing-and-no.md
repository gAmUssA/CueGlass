---
# cueglass-pili
title: Apple Developer account integration, signing, and notarization
status: todo
type: task
priority: high
created_at: 2026-10-14T13:34:22Z
updated_at: 2026-10-14T13:34:22Z
parent: cueglass-ffq6
blocked_by:
    - cueglass-aeqt
---

Integrate the owner’s Apple Developer account and prepare a distributable signed CueGlass build.

Acceptance:
- Record Developer Team ID and real bundle identifier in owner-only configuration.
- Configure signing, entitlements, and release build settings without committing secrets.
- Sign the release with the intended distribution identity.
- Submit for notarization, staple the ticket, and verify Gatekeeper assessment on a clean machine/install.
- Document reproducible build and notarization commands and results.
