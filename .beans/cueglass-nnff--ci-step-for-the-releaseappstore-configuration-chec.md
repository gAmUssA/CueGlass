---
# cueglass-nnff
title: CI step for the ReleaseAppStore configuration check
status: todo
type: task
priority: low
created_at: 2026-11-03T17:47:26Z
updated_at: 2026-11-03T18:50:18Z
parent: cueglass-gzi5
---

Wire scripts/test-app-store-config.sh into .github/workflows/macos-release.yml as a CI-scoped change. It builds ReleaseAppStore unsigned and asserts bundle id, the three provisional entitlement keys, hardened runtime and Info.plist keys (ADR 0016), and runs scripts/check-fastfile-shared-values.rb through bundle exec, which needs the project-local vendor/bundle (bundle install) on the runner. Not wired in the ADR 0016 change because workflow edits need their own CI-scoped PR.

- [ ] Add the workflow step in a PR scoped as a CI change
- [ ] Confirm the step runs green in Actions
