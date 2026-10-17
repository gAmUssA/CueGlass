---
# cueglass-lw2i
title: Preserve anchors and running state after chunked measurement
status: completed
type: bug
priority: high
created_at: 2026-10-13T23:11:38Z
updated_at: 2026-10-17T19:58:52Z
parent: cueglass-aeqt
---

Independent broad review r4 at4eef1df establishes two mandatory-contract failures: R4-1 near-end font64→120 restoration clamps to obsolete end (offset7990→2490); R4-2 asynchronous surface resume replays countdown while synchronous short-script path stays running. Both concern measurement completion ordering. Same cueglass-v1 originalbase13bd9b6 and cumulativefix5; no automaticfix6. Existing allowance exhausted: require assessed investigator and pinned judge diagnosis before code correction.

## Acceptance

- [x] Preserve independent reproductions and long/short discriminator
- [x] Investigate cause and test a discriminating counterfactual without canonical source edits
- [x] Record bounded diagnosis under original task/base/count
- [x] Correct anchor and resume intent while preserving cancellation, source, snapshot, LPM and single clock
- [x] Add meaningful long-script asynchronous regressions and pass normal full suite
- [x] Independent final-tip whole-branch verification, including native checks when GUI available. At 03d8df798f0e74121274e3e4d5a7990103b0099c: R6 (scoped R5-1/Q4 recheck passes independently), R7 (full whole-branch textual review PASS), T5 (Mode C full verification: R5-1 and the Q4 geometry residual RESOLVED) and T6 (GUI completion on the unlocked session); reports /Users/vikgamov/.local/state/cueglass/r6.md, r7.md, t5.md, t6.md. Shipped in PR #3 (merge 16c81eb) and every release since v0.1.0.

Fix6 implementation: completion-time anchor restoration for all five callers; retained original anchor across superseding measurement; distinct resume/start intent; navigation cancellation; Stop clears measuring; final-geometry Timed re-solve preserves remaining playing time. Native matrix added. Intermediate fixed tip passed 29 native tests, core14, ReleaseLocal, formatting and Beans; three discriminating counterfactuals failed as expected. Final added Timed/Restart regression fails (30 tests, two assertions): remaining-time rebasing loses original Restart budget. Scope decision required before delivery; no fix6 commit or push. Independent acceptance remains open.

## Fix6 scope blocker

- [x] Preserve the original Timed budget and elapsed baseline through preparation and Restart, without rebasing away Restart semantics.

Controller-only remaining-seconds restoration changes a 600-second plan with 10 seconds elapsed into a 590-second plan. Restart during pending measurement then finishes in 590 seconds, although it resets elapsed to zero. PlaybackSession owns private timedDuration/timedElapsedBase and its updateLayout/seek methods destructively clear infeasible interim plans. Requested lead decision: authorize a narrow PlaybackSession timing-intent API change (no core/viewport change), or specify an accepted Controller-only preservation design. Evidence and retained failing regression: /Users/vikgamov/.local/state/cueglass/d7.md and d7-restart-before.log. All source/test/Bean edits are uncommitted and preserved in cueglass-native.

## Fix7 checkpoint — blocked before commit/push

J2 atomic Session layout/position update and truthful Restart cancellation implemented; deleted remaining-time rebasing state. Added six deterministic native regressions (36 total), covering completed and in-flight Restart, late-enabled elapsed base, actual running floating resize/fullscreen, navigation, infeasible Restart/manual Play and Session atomic geometry. All Timed regressions pass. Full native suite fails two unchanged short-script anchor assertions: scenario3 restores 13087 before updateLayout versus 13485.6 afterward, changing offset782 to751. Baseline D7 passes this anchor case. Conditional position application experiment did not change the failure. No existing assertion removed or weakened. Needs an accepted geometry-ordering decision within J2; no commit/push. Evidence: /Users/vikgamov/.local/state/cueglass/d8.md.

- [x] Resolve synchronous short-script anchor regression introduced by atomic completion ordering and pass the full suite.

## Fix8 implementation evidence

Integrated two bounded measurement passes with generation guards and an intervening viewport geometry query before the single atomic Session update. Measuring stays true until the final callback; pending start/resume are consumed once. Retained all 36 existing native tests unchanged. Added final-fragment geometry regression across 20/64/65/200 paragraphs, penultimate/final paragraph anchors, typography and actual floating resize, Timed deadline and Restart. Full native37 passes. Atomic-mechanism counterfactual fails24 issues; one-query counterfactual fails85 issues including stale cached/bound final-end mismatch1131.8pt. Exact final source restored by SHA256. Initial preparation performs two bounded traversals; hardware profiling should measure this overhead. Independent final-tip verification remains open. Full round evidence: /Users/vikgamov/.local/state/cueglass/d9.md.

## Independent R5 cancellation finding — confirmed full blocking review

- [x] Preserve an explicit pause/cancel through queued preparation completion for output/floating close, sleep, Restart and scrub.

At ef3dc80, independent report-local r5-probe.swift/log reproduces five failures: each command pauses immediately, but pendingResume stays true and measurement completion resumes playback. Geometry/actual-end and Timed end-hold checks pass for 20/64/65/200. Full R5 report is delivered; assessed investigation and bounded diagnosis remain required before another code attempt; no automatic fix9. Existing J2 fixes7–8 are exhausted. Evidence: /Users/vikgamov/.local/state/cueglass/r5-probe-exit0.log. Current suite37 does not cover this cancellation overlap.

R5 full report delivered and recorded blocking at ef3dc80: /Users/vikgamov/.local/state/cueglass/r5.md. Existing fix8 allowance is exhausted; checkpoint cueglass-cancellation-after-fix8 records required assessed investigation and descending pinned-judge diagnosis. Q3 Axiom investigation dispatched; no new product-code correction authorized yet.

## Q3 preview-end observation triage

- [x] Distinguish a lazy preview-fragment estimate from a real final-end mismatch after presentation closes, using report-local bounded layout measurement and recorded pre-query state. Q3 Finding 4 is unproven and is not an implementation authorization.

## Confirmed in-flight close geometry residual

- [x] Keep Session end equal to fully settled current-layout end when closing output/floating or losing output during the first preparation pass, while preserving cancellation and running-navigation semantics.

Lead bounded measurement control: settled-then-close provisional preview query differs, but two full bounded preview passes match the retained Session bound exactly. In-flight close is different: eight cases retain a real short bound after final geometry settles (floating 296.4pt, output close/loss 1132pt, resized floating 395.2pt). Source callback switches from the first-pass surface to dynamic authoritative preview for the second pass. Evidence: /Users/vikgamov/.local/state/cueglass/lead-q3-preview-end/matrix-run.log and run.log. Q3 intent candidate passes684 intent checks and37 inherited tests but does not resolve this geometry overlap. Same full R15 contract, no new feature or automatic correction allowance; follow-up assessed investigation precedes pinned-judge diagnosis.

## Fix9 authorization

J3 diagnosis delivered and recorded as cueglass-owner-invariants-plan:plan, restructure bound1 at original cueglass-v1/base13bd9b6/count8. One fresh developer attempt fix9 authorized. Adopt assessed Q4 cfR owner-held deferred start and measured viewport identity guards; native regressions first, unchanged700 intent +368 geometry probe gates independently rerun. Two implementation residuals remain unchecked until proven; independent whole-branch acceptance remains open. Evidence /Users/vikgamov/.local/state/cueglass/j3.md and j3-diagnose-receipt.json.

## Fix9 implementation evidence

Applied the assessed Q4 cfR candidate under cueglass-owner-invariants-plan:plan, with only the two known computed-setter formatting wraps. Session pause transitions withdraw deferred starts; render pins both bounded passes and re-prepares when viewport authority changes. Appended six native tests without changing any inherited37 definition. Regressions-first normal scheme on ef3 fails52 issues (exit65); cfI-only clears intent failures but fails9 geometry issues (exit65); exact final cfR passes43 tests. Coverage includes both passes for floating/output pause actions, preserving navigation, close/end/paragraph anchor, Timed600/10/590/message and second-document claim. Independent final-tip acceptance remains unchecked; no PR/merge. Full evidence: /Users/vikgamov/.local/state/cueglass/d10.md.

Fix9 final local gates: full normal DebugLocal scheme43/43; unchanged q4-probe700 intent/0 failures and368 GEO/0 failures; Core14/14; ReleaseLocal BUILD SUCCEEDED; strict swift-format zero diagnostics; beans check and diff check pass. Production bytes equal assessed cfR with only known setter wrapping. Independent reviewer/tester acceptance remains open.

## Summary of Changes

Completion-time anchor restoration, distinct resume/start intent, owner-held deferred starts, two bounded measurement passes with generation guards and viewport-identity re-preparation shipped with the MVP (PR #3, merge 16c81eb) and are exercised by the native suite on every release through v0.3.0 (172 native tests at this Bean's closing tip; v0.3.0 publish run 39061330997). Independent whole-branch verification at 03d8df7 (R6, R7, T5, T6) recorded the R5-1 and Q4 findings as resolved. Hardware smoothness and the 60-minute soak remain in cueglass-feeg and cueglass-c1kt.
