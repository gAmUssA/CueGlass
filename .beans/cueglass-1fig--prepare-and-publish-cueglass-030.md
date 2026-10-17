---
# cueglass-1fig
title: Prepare and publish CueGlass 0.3.0
status: in-progress
type: task
priority: normal
created_at: 2026-10-17T04:58:08Z
updated_at: 2026-10-17T19:58:52Z
---

Prepare the completed Claude Camera Dock, microphone continuity, and Quiet Studio work for the next release. User authorization: initiate preparation for merge and cutting next release.

- [x] Reconcile developer report and tracking dependencies.
- [x] Prepare version 0.3.0, changelog and release notes.
- [x] Obtain independent full-branch reviewer and tester verdicts.
- [x] Resolve blocking findings and document remaining hardware observations. Blocking findings closed through cueglass-f01c, cueglass-nj97, cueglass-j71o, cueglass-ssfp and cueglass-ta8r (final7 independent re-check PASS, review 5559397563 at e021d43); the owner's three accepted r11 observations and every remaining Pending row are recorded in docs/MANUAL_TEST_PLAN.md and carried in cueglass-feeg.
- [x] Open PR, pass CI and review gates, merge, and publish unsigned/unnotarized GitHub assets. PR #5 (release(cueglass): ship CueGlass 0.3.0), exact-head CI 39057584583 success, merged 2026-10-17T19:10:44Z as 80d23b81f641164eeaff695169e791637cb9db93; tag v0.3.0 at that merge; publish run 39061330997 success; prerelease published 2026-10-17T19:18:11Z with CueGlass-v0.3.0-macOS-UNSIGNED-UNNOTARIZED.zip, its .sha256 and UNNOTARIZED.txt.
- [x] Verify downloadable assets. Downloaded from the v0.3.0 release on 2026-10-17: `shasum -a 256 --check` OK and `unzip -t` reports no errors.
- [ ] Clean up merged worktrees. On 2026-10-17 `git worktree list` still shows cueglass-release-030 (release/cueglass-030, merged), cueglass-030-tester, cueglass-030-final-reviewer/-tester, cueglass-030-final2-reviewer/-tester and cueglass-030-final3-reviewer; the lead owns their removal.

## Preparation result — 2026-10-17

Candidate 322b05567c647f096d04f049ba39412e38dc889c passed Core 108, native 134, direct runner 134, strict formatting, Beans integrity, universal ReleaseLocal 0.3.0/build 3 with macOS 14 metadata, and GitHub Actions run 39004563879. Both independent full reports are blocking: microphone default/selected routing and rejected-device handling; tap ownership during startup/reconfiguration; Collapse manual takeover; controls at width/nudge boundaries; calibrated preview reflection/guide agreement; accepted ADR mutation and contradictory manual instructions. Correction Bean cueglass-f01c continues original task cueglass-tgvc as correction 1 with Claude/Axiom. No PR, merge or tag has been created.

Owner confirmed all three r11 checks passed: notch attachment/animation, main preview next to editor, microphone selection/switching. This does not claim unmentioned hardware or macOS 14 runtime rows passed. Reports and reproducible probes: /Users/vikgamov/.local/state/cueglass/release-030/reports/reviewer.md and tester.md. Release remains in progress until corrections, final independent verification and publication are complete.

## Final candidate integration

Integrated all six Claude correction commits from 95f761e into the 0.3.0 release branch. Version 0.3.0/build 3 preserved. Prior findings now await independent re-verification against the full main-to-candidate range; owner acceptance remains recorded. User explicitly requested carrying this through merge and release.



## PR #5 gate checkpoint — 2026-10-17

PR #5 is open on release/cueglass-030 at a8ac7c6b6121d5bf4078e9b6aec9798701856f7c. Exact-head pull_request CI run 39038057328 succeeded. Copilot review 5558087329 reported eight source defects; the release lead confirmed them and blocked merge. Correction3 is tracked in cueglass-f01c. PR remains open; no merge, v0.3.0 tag, or publication yet. Preserve the owner-authorized deferral of unverified hardware/macOS14 rows; no signing or notarization.

## Four-finding follow-up — 2026-10-17

Bean cueglass-nj97 implements the assigned four corrections from Copilot review 5558332476 on candidate a059bce903e9f02d2a7eae2eff0849dd400e87e3, in fix/cueglass-030-followup. The audio counter now shares its reader lock, failed Output recovery cancels deferred resume, pending Load Latest failures remain visible, and attached Dock fit uses resolved height. Each has regression coverage; the original source failed the focused regressions (the audio race under Thread Sanitizer).

Local gates pass: 114 Core tests, 162 native tests through both xcodebuild and the direct runner, focused Thread Sanitizer, strict formatting, Beans integrity, diff whitespace, universal unsigned ReleaseLocal build and ZIP/checksum validation. Built metadata remains 0.3.0/build 3, minimum macOS 14.0. This branch awaits independent tester/reviewer verification before integration; it does not supersede release acceptance or mark any pending hardware row complete. No merge, tag or publication occurs in this assignment.

## Release landed — 2026-10-17

v0.3.0 is merged and published (details on the checklist above). This Bean stays in progress only for the worktree cleanup, which is the lead's housekeeping; the shipped feature and correction Beans were completed on 2026-10-17 with their unverified hardware rows moved to cueglass-feeg. Follow-up issues #6 and #7 are tracked in cueglass-w4c7.
