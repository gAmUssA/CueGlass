---
# cueglass-ffq6
title: CueGlass Signed Distribution and iCloud
status: todo
type: milestone
priority: high
created_at: 2026-10-14T13:34:21Z
updated_at: 2026-10-14T13:34:21Z
blocked_by:
    - cueglass-aeqt
---

Follow-up to the local-first CueGlass MVP. This milestone owns Apple Developer account/team integration, signed macOS distribution and notarization, plus owner-configured iCloud setup and two-Mac sync verification.

Acceptance:
- Owner supplies the Developer Team ID, real bundle ID, and iCloud container ID.
- Configure signing, entitlements, and the actual iCloud container for distribution builds.
- Produce a signed release, notarize and staple it, then verify Gatekeeper assessment on a clean install.
- Verify iCloud save/open across two Macs, offline conflict recovery, cloud-only files, account changes, and running-take isolation.

Do not claim signed distribution or real iCloud synchronization until owner credentials and end-to-end evidence are recorded. App Store submission is outside this milestone unless separately requested.
