---
# cueglass-pili
title: Apple Developer account integration, signing, and notarization
status: todo
type: task
priority: high
created_at: 2026-10-14T13:34:22Z
updated_at: 2026-11-03T03:47:52Z
parent: cueglass-gzi5
blocked_by:
    - cueglass-aeqt
    - cueglass-sx4d
---

Integrate the owner’s Apple Developer account and prepare a distributable signed CueGlass build.

Acceptance:
- Record Developer Team ID and real bundle identifier in owner-only configuration.
- Configure signing, entitlements, and release build settings without committing secrets.
- Sign the release with the intended distribution identity.
- Submit for notarization, staple the ticket, and verify Gatekeeper assessment on a clean machine/install.
- Document reproducible build and notarization commands and results.

## Competitor research link (2026-11-03)

Signed and notarized distribution is the largest install-trust gap versus CueNotch, Notchie, NotchPrompter and Notch. Tracked in epic cueglass-2ur9.

## Operator decision (2026-11-03)

Publish on the Mac App Store at 3.99 USD to cover the Apple Developer fee (also needed for notarization of the direct download). The source stays free and MIT. Needs the sandbox spike first, see the epic.
