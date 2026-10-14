---
# cueglass-u5ni
title: GitHub Actions build and unnotarized release asset
status: completed
type: task
priority: high
created_at: 2026-10-14T13:37:02Z
updated_at: 2026-10-14T14:57:51Z
parent: cueglass-aeqt
---

Add a public-repository GitHub Actions release pipeline for the local CueGlass MVP. On a version tag, run the native macOS validation/build, package the macOS app as a clearly labelled UNNOTARIZED zip with SHA-256 checksum and a plain status notice, and publish the assets to a GitHub Release using standard GitHub-hosted macOS runners and the repository GITHUB_TOKEN. Keep credentials out of the workflow; do not provide Gatekeeper bypass instructions. Acceptance: workflow validates/builds on the supported macOS runner; tag push creates a public release with app zip/checksum/unnotarized notice and release notes explaining that notarization is deferred; README explains release trigger and status; no signing credentials required.


## Checklist

- [x] Add pull-request/manual validation and version-tag GitHub Actions workflow on a standard macOS runner.
- [x] Build universal arm64/x86_64 unsigned app; package ZIP, checksum and unsigned/unnotarized notice.
- [x] Publish only from semantic version tags as an explicitly unsigned/unnotarized prerelease.
- [x] Update README, changelog, ADR and local-first MVP scope for GitHub releases and deferred iCloud/signing.
- [x] Rerun workflow on GitHub-hosted macOS after the final test-fixture stabilization; verify tests, universal build and packaging.
- [x] Verify the public v0.1.0 prerelease and every uploaded asset; download, checksum, ZIP integrity and universal architecture checks pass.

- [x] Set repository visibility to public and verify it is now public (`gh repo view`).

- [x] Stabilize the two-pass navigation test fixture after hosted CI exposed a timing-sensitive measuring assertion.

- [x] Correct `lipo` architecture verification syntax for the hosted macOS 26 toolchain.

- [x] Re-run the 48-test native app suite locally after raising the shared preparation fixture default to 300 paragraphs; strict Swift formatting and Beans integrity checks pass.

- [x] Keep close-handoff and timed-close fixtures asynchronous with 300 paragraphs, preserving the timed feasibility cap; the local 48-test suite passes.

- [x] Fix the Ubuntu release publisher to pass the repository explicitly to `gh release create`; the first tag build passed but publication exposed missing GitHub CLI repository context.

## Summary of Changes

Published the unsigned/unnotarized universal macOS app as the public [v0.1.0 GitHub prerelease](https://github.com/gAmUssA/CueGlass/releases/tag/v0.1.0). The [tag workflow](https://github.com/gAmUssA/CueGlass/actions/runs/38584524965) passed Core and native tests, strict formatting, universal arm64/x86_64 build, and packaging. Downloaded the release ZIP and verified its SHA-256, archive integrity, and both binary architectures. Fixed hosted-test fixture timing and the publisher repository context.
