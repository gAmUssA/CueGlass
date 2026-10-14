---
# cueglass-lw2i
title: Preserve anchors and running state after chunked measurement
status: in-progress
type: bug
priority: high
created_at: 2026-10-13T23:11:38Z
updated_at: 2026-10-14T01:34:01Z
parent: cueglass-aeqt
---

Independent broad review r4 at4eef1df establishes two mandatory-contract failures: R4-1 near-end font64→120 restoration clamps to obsolete end (offset7990→2490); R4-2 asynchronous surface resume replays countdown while synchronous short-script path stays running. Both concern measurement completion ordering. Same cueglass-v1 originalbase13bd9b6 and cumulativefix5; no automaticfix6. Existing allowance exhausted: require assessed investigator and pinned judge diagnosis before code correction.

## Acceptance

- [x] Preserve independent reproductions and long/short discriminator
- [x] Investigate cause and test a discriminating counterfactual without canonical source edits
- [x] Record bounded diagnosis under original task/base/count
- [x] Correct anchor and resume intent while preserving cancellation, source, snapshot, LPM and single clock
- [x] Add meaningful long-script asynchronous regressions and pass normal full suite
- [ ] Independent final-tip whole-branch verification, including native checks when GUI available

Fix6 implementation: completion-time anchor restoration for all five callers; retained original anchor across superseding measurement; distinct resume/start intent; navigation cancellation; Stop clears measuring; final-geometry Timed re-solve preserves remaining playing time. Native matrix added. Intermediate fixed tip passed 29 native tests, core14, ReleaseLocal, formatting and Beans; three discriminating counterfactuals failed as expected. Final added Timed/Restart regression fails (30 tests, two assertions): remaining-time rebasing loses original Restart budget. Scope decision required before delivery; no fix6 commit or push. Independent acceptance remains open.

## Fix6 scope blocker

- [x] Preserve the original Timed budget and elapsed baseline through preparation and Restart, without rebasing away Restart semantics.

Controller-only remaining-seconds restoration changes a 600-second plan with 10 seconds elapsed into a 590-second plan. Restart during pending measurement then finishes in 590 seconds, although it resets elapsed to zero. PlaybackSession owns private timedDuration/timedElapsedBase and its updateLayout/seek methods destructively clear infeasible interim plans. Requested lead decision: authorize a narrow PlaybackSession timing-intent API change (no core/viewport change), or specify an accepted Controller-only preservation design. Evidence and retained failing regression: /Users/vikgamov/.local/state/cueglass/d7.md and d7-restart-before.log. All source/test/Bean edits are uncommitted and preserved in cueglass-native.

## Fix7 checkpoint — blocked before commit/push

J2 atomic Session layout/position update and truthful Restart cancellation implemented; deleted remaining-time rebasing state. Added six deterministic native regressions (36 total), covering completed and in-flight Restart, late-enabled elapsed base, actual running floating resize/fullscreen, navigation, infeasible Restart/manual Play and Session atomic geometry. All Timed regressions pass. Full native suite fails two unchanged short-script anchor assertions: scenario3 restores 13087 before updateLayout versus 13485.6 afterward, changing offset782 to751. Baseline D7 passes this anchor case. Conditional position application experiment did not change the failure. No existing assertion removed or weakened. Needs an accepted geometry-ordering decision within J2; no commit/push. Evidence: /Users/vikgamov/.local/state/cueglass/d8.md.

- [x] Resolve synchronous short-script anchor regression introduced by atomic completion ordering and pass the full suite.

## Fix8 implementation evidence

Integrated two bounded measurement passes with generation guards and an intervening viewport geometry query before the single atomic Session update. Measuring stays true until the final callback; pending start/resume are consumed once. Retained all 36 existing native tests unchanged. Added final-fragment geometry regression across 20/64/65/200 paragraphs, penultimate/final paragraph anchors, typography and actual floating resize, Timed deadline and Restart. Full native37 passes. Atomic-mechanism counterfactual fails24 issues; one-query counterfactual fails85 issues including stale cached/bound final-end mismatch1131.8pt. Exact final source restored by SHA256. Initial preparation performs two bounded traversals; hardware profiling should measure this overhead. Independent final-tip verification remains open. Full round evidence: /Users/vikgamov/.local/state/cueglass/d9.md.
