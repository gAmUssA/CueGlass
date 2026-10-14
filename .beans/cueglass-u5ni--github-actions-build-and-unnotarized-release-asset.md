---
# cueglass-u5ni
title: GitHub Actions build and unnotarized release asset
status: in-progress
type: task
priority: high
created_at: 2026-10-14T13:37:02Z
updated_at: 2026-10-14T14:25:15Z
parent: cueglass-aeqt
---

Add a public-repository GitHub Actions release pipeline for the local CueGlass MVP. On a version tag, run the native macOS validation/build, package the macOS app as a clearly labelled UNNOTARIZED zip with SHA-256 checksum and a plain status notice, and publish the assets to a GitHub Release using standard GitHub-hosted macOS runners and the repository GITHUB_TOKEN. Keep credentials out of the workflow; do not provide Gatekeeper bypass instructions. Acceptance: workflow validates/builds on the supported macOS runner; tag push creates a public release with app zip/checksum/unnotarized notice and release notes explaining that notarization is deferred; README explains release trigger and status; no signing credentials required.


## Checklist

- [x] Add pull-request/manual validation and version-tag GitHub Actions workflow on a standard macOS runner.
- [x] Build universal arm64/x86_64 unsigned app; package ZIP, checksum and unsigned/unnotarized notice.
- [x] Publish only from semantic version tags as an explicitly unsigned/unnotarized prerelease.
- [x] Update README, changelog, ADR and local-first MVP scope for GitHub releases and deferred iCloud/signing.
- [ ] Rerun workflow on GitHub-hosted macOS after the final test-fixture stabilization; verify tests, universal build and packaging.
- [ ] Verify a tagged prerelease and each uploaded asset are retrievable after MVP acceptance.

- [x] Set repository visibility to public and verify it is now public (`gh repo view`).

- [x] Stabilize the two-pass navigation test fixture after hosted CI exposed a timing-sensitive measuring assertion.

- [x] Correct `lipo` architecture verification syntax for the hosted macOS 26 toolchain.

- [x] Re-run the 48-test native app suite locally with the final 300-paragraph close-handoff and timed-close fixtures; strict Swift formatting and Beans integrity checks pass.

- [x] Keep close-handoff and timed-close fixtures asynchronous with 300 paragraphs, preserving the timed feasibility cap; the local 48-test suite passes.
