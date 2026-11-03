---
# cueglass-h2tz
title: Set up fastlane for the Mac App Store build
status: todo
type: task
priority: high
created_at: 2026-11-03T03:47:52Z
updated_at: 2026-11-03T03:47:52Z
parent: cueglass-gzi5
blocked_by:
    - cueglass-sx4d
---

Add a Gemfile and lock (Bundler) with fastlane, a Fastfile with lanes for build_mac_app (gym), match signing and deliver. Stated new dependency: fastlane; stdlib alternative xcodebuild plus notarytool scripts rejected because deliver handles metadata and screenshots. Add Dependabot for bundler. Installing Ruby or fastlane on a machine needs the owner's yes.

- [ ] Gemfile, lock, Dependabot
- [ ] Fastfile lanes: build, beta (TestFlight), release
- [ ] Document secrets in .env.example, none committed
