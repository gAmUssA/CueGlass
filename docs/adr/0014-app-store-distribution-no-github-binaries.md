# Title

Mac App Store distribution; GitHub publishes no binaries

# Status

accepted

# Date

2026-11-03

# Context

ADR 0006 ordered a tag-triggered GitHub Actions workflow that published an unsigned, unnotarized prerelease ZIP. The owner now sells signed CueGlass builds on the Mac App Store, while the source stays free under the MIT license. Free binaries on GitHub Releases would compete with the paid build and bypass signing. The existing 0.3.0 GitHub prerelease stays until the owner says otherwise.

# Decision

Supersedes ADR 0006. `.github/workflows/macos-release.yml` runs the format check, core tests, native tests and the universal arm64/x86_64 `ReleaseLocal` build on pull requests, branch pushes and manual dispatch. It does not run on tags and publishes no release, ZIP, checksum or notice. The build job keeps `contents: read`, and the `lipo` architecture check stays as build validation. The workflow file name, workflow name and job id `build-and-package` stay. Signed builds are sold on the Mac App Store; signing and App Store submission stay in the Apple Developer account milestone. Never describe an unsigned build as signed or notarized, and do not publish Gatekeeper bypass instructions.

# Consequences

New binaries do not appear on GitHub Releases. Until a signed App Store build exists, install is from source. The MIT LICENSE file is tracked in bean `cueglass-ev4z`. Deleting or relabeling the 0.3.0 prerelease remains an open item in bean `cueglass-p76i`. Later work must not reintroduce a binary-publishing job or a tag trigger without a new ADR.
