# Title

Public GitHub Actions build and unnotarized prerelease assets

# Status

accepted

# Date

2026-10-14

# Context

The local-first CueGlass MVP needs downloadable macOS binaries without requiring users to build the app. Apple Developer account integration, Developer ID signing, notarization and iCloud validation are deferred to the next milestone. The repository owner permits public source visibility; standard GitHub-hosted runners are free for public repositories, while larger runners can incur charges.

# Decision

Use a tag-triggered GitHub Actions workflow on the standard `macos-26` runner. Pull requests and manual dispatch validate and build only; a `vMAJOR.MINOR.PATCH` tag runs the tests, creates an arm64/x86_64 unsigned `ReleaseLocal` app, verifies its ZIP and SHA-256 checksum, then publishes a prerelease with an explicit unsigned/unnotarized status notice. The build job has read-only repository access; a separate tag-only release job gets `contents: write` to publish the assets. No signing credentials are needed. Keep Apple signing, notarization and iCloud setup in the follow-up milestone. Do not publish Gatekeeper bypass instructions.

# Consequences

Users can download a reproducible prerelease binary and checksum from GitHub Releases, and the build does not require an Apple Developer account. The initial binary is unsigned and not notarized, so macOS may prevent it from opening; it is a testing artifact, not a signed distribution. Public source visibility is required for the intended free standard-runner usage. The release workflow must not use larger runners. A future signed release supersedes this prerelease path for normal distribution.
