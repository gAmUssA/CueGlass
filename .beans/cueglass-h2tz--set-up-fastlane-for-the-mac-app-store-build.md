---
# cueglass-h2tz
title: Set up fastlane for the Mac App Store build
status: in-progress
type: task
priority: high
created_at: 2026-11-03T03:47:52Z
updated_at: 2026-11-03T17:47:44Z
parent: cueglass-gzi5
blocked_by:
    - cueglass-sx4d
---

Add a Gemfile and lock (Bundler) with fastlane, a Fastfile with lanes for build_mac_app (gym), match signing and deliver. Stated new dependency: fastlane; stdlib alternative xcodebuild plus notarytool scripts rejected because deliver handles metadata and screenshots. Add Dependabot for bundler. Installing Ruby or fastlane on a machine needs the owner's yes.

- [ ] Gemfile, lock, Dependabot
- [ ] Fastfile lanes: build, beta (TestFlight), release
- [x] Document secrets in .env.example, none committed
- [ ] Run the lanes against real App Store Connect credentials (owner-only, NOT RUN)
- [ ] Decide whether to adopt match; the lanes use automatic signing with the API key instead (ADR 0016)
- [ ] Add listing metadata and screenshots, then drop skip_metadata and skip_screenshots from the release lane

## Progress (2026-11-03)

fastlane 2.241.2 is pinned with a committed lock; `bundle exec fastlane lanes` lists build, beta and release (OBSERVED); `mac build` without credentials stops naming the missing variables (OBSERVED). No lane ran against real credentials, and no signed build, upload or submission ran (NOT RUN). See ADR 0016 (proposed).
