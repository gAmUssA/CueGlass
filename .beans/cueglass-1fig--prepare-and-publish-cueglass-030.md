---
# cueglass-1fig
title: Prepare and publish CueGlass 0.3.0
status: in-progress
type: task
priority: normal
created_at: 2026-10-17T04:58:08Z
updated_at: 2026-10-17T05:11:54Z
---

Prepare the completed Claude Camera Dock, microphone continuity, and Quiet Studio work for the next release. User authorization: initiate preparation for merge and cutting next release.

- [x] Reconcile developer report and tracking dependencies.
- [x] Prepare version 0.3.0, changelog and release notes.
- [x] Obtain independent full-branch reviewer and tester verdicts.
- [ ] Resolve blocking findings and document remaining hardware observations.
- [ ] Open PR, pass CI and review gates, merge, and publish unsigned/unnotarized GitHub assets.
- [ ] Verify downloadable assets and clean up merged worktrees.

## Preparation result — 2026-10-17

Candidate 322b05567c647f096d04f049ba39412e38dc889c passed Core 108, native 134, direct runner 134, strict formatting, Beans integrity, universal ReleaseLocal 0.3.0/build 3 with macOS 14 metadata, and GitHub Actions run 39004563879. Both independent full reports are blocking: microphone default/selected routing and rejected-device handling; tap ownership during startup/reconfiguration; Collapse manual takeover; controls at width/nudge boundaries; calibrated preview reflection/guide agreement; accepted ADR mutation and contradictory manual instructions. Correction Bean cueglass-f01c continues original task cueglass-tgvc as correction 1 with Claude/Axiom. No PR, merge or tag has been created.

Owner confirmed all three r11 checks passed: notch attachment/animation, main preview next to editor, microphone selection/switching. This does not claim unmentioned hardware or macOS 14 runtime rows passed. Reports and reproducible probes: /Users/vikgamov/.local/state/cueglass/release-030/reports/reviewer.md and tester.md. Release remains in progress until corrections, final independent verification and publication are complete.
