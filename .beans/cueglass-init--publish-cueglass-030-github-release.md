---
# cueglass-init
title: Publish CueGlass 0.3.0 GitHub release
status: scrapped
type: task
priority: normal
created_at: 2026-10-17T13:46:10Z
updated_at: 2026-10-17T13:54:53Z
---

## Checklist

- [x] Finalize the 0.3.0 candidate and independent review/test reports.
- [x] Confirm exact-tip GitHub Actions success.
- [x] Open PR #5, request Copilot, and pass PR CI on exact head a8ac7c6b6121d5bf4078e9b6aec9798701856f7c. Copilot review is pending.
- [ ] Merge to main and verify main CI.
- [ ] Tag v0.3.0 and verify the GitHub release assets and checksums.
- [ ] Clean the release worktree and branch; record outstanding device checks.

Owner authorized an unsigned, unnotarized GitHub release. Extra physical/macOS 14 runtime checks remain unverified follow-up; signing and notarization are deferred.



## Reasons for Scrapping

The release already has its canonical in-repository Bean cueglass-1fig on the release branch; this duplicate was created in the shared checkout before I noticed that tracked issue.
