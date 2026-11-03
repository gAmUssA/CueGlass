---
# cueglass-p76i
title: 'CI: stop publishing binaries, keep build and tests'
status: completed
type: task
priority: high
created_at: 2026-11-03T03:47:52Z
updated_at: 2026-11-03T03:47:52Z
parent: cueglass-qe15
---

CI-scope change; announce it as such in the PR. Edit .github/workflows/macos-release.yml: keep format, core and native tests and the universal build on PRs and branch pushes; remove the tag-triggered publish-release job and its ZIP, checksum and notice steps.

- [x] Remove publish-release job
- [x] Add superseding ADR 0014 (replaces ADR 0006)
- [x] Confirm PR checks still run build-and-package
- [x] Mark the 0.3.0 prerelease notes as superseded (deleting the release needs the owner's yes)

## Summary of Changes

PR #16 run 41579828532 showed job build-and-package (merge commit ebea598). The v0.3.0 release notes now begin with a Superseded notice, edited by the lead on 2026-11-03; the release itself is kept.
