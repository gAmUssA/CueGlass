---
# cueglass-p76i
title: 'CI: stop publishing binaries, keep build and tests'
status: todo
type: task
priority: high
created_at: 2026-11-03T03:47:52Z
updated_at: 2026-11-03T03:47:52Z
parent: cueglass-qe15
---

CI-scope change; announce it as such in the PR. Edit .github/workflows/macos-release.yml: keep format, core and native tests and the universal build on PRs and branch pushes; remove the tag-triggered publish-release job and its ZIP, checksum and notice steps.

- [x] Remove publish-release job
- [ ] Confirm PR checks still run build-and-package
- [ ] Mark the 0.3.0 prerelease notes as superseded (deleting the release needs the owner's yes)
