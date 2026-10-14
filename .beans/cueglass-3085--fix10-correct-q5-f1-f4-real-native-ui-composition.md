---
# cueglass-3085
title: 'Fix11: correct native composition oracles and Dark editor readability under J5'
status: in-progress
type: bug
priority: normal
created_at: 2026-10-14T06:44:24Z
updated_at: 2026-10-14T09:13:07Z
parent: cueglass-aeqt
---

Implement J4 allowed UI/test/metadata paths. Independent foreground acceptance pending.

- [x] Read binding evidence and consumers
- [x] Append four regressions and record baseline failures
- [x] Implement the one authorized Fix11 correction from J5's binding oracle interpretations and Dark rendering finding
- [x] Run all required gates
- [x] Commit the local candidate after all required local gates pass; leave it unpushed for lead review and foreground verification.

Baseline canonical03d8 plus four regressions: exit65, 47 tests/19 issues; all four new oracles fail. Log d11-native-baseline-tests.log. Initial test compilation used unavailable NSLayoutGuide.layoutFrame; corrected to bounds/safeAreaInsets before actual baseline run.

## Fix11 progress

J5 diagnosis (j5.md) verified the partial Fix10 state and classifies the literal priority-50 fittingSize assertion, paint-order occlusion walk, Dark fragment-draw oracle, and ratio tolerance as invalid oracles; it confirms the Dark refresh is a real defect and the persisted inspectorCollapsed preference makes collapse coverage order-dependent. The owner recorded the judge's stop at fix round 10, then recorded the user's exact authorization as one Fix11 attempt only under the unchanged J4 scope and paths. The fitting minimum oracle is the drag-priority-510 width from balanced 1280×800; Dark must explicitly reapply display-only rendering attributes; ratio assertions use contract-window frames and a 0.5 pt rounding bound; the volatile-domain pin must reach the xctest process. Do not reset the user's XCTest preference plist. The corrected oracle counterfactual fails on canonical 03d8df7. Required local gates now pass. Independent source/test review, owned-window foreground capture, and product acceptance remain with the lead.

## Partial Changes

Four new tests appended; all 43 inherited definitions remain byte-prefix unchanged. Canonical baseline actual 47 tests/19 issues, exit 65; all four new tests fail. Applied fullSize/safe-area pins, native inspector priorities 490/480 and controller-owned explicit collapse, HUD focusable(false), and the initial rendering-only Dark validator. The same 47 tests reran at exit 65/9 issues during Fix10; the responder test passes. Required local gates now pass. Independent source/test review and foreground real-path verification remain with the lead.

\n\n## J5 diagnosis and one-attempt override\n\nJ5 report: /Users/vikgamov/.local/state/cueglass/j5.md (SHA-256 56384437d2a3d21ca9648ad5e35905ae4bc223dadbf39351efdf489c558e8e87). Owner diagnosis: /Users/vikgamov/.local/state/cueglass/j5-diagnose-receipt.json. The operator override is recorded as Fix11 only, with all required gates before any push: /Users/vikgamov/.local/state/cueglass/j5-authorize-corrections-receipt.json. Preserve the partial Fix10 worktree and the original base/count. After the single attempt, all required local source/test gates and independent two-tier verification remain open.


## Fix11 dispatch preparation — 2026-10-14

J5's stop attention item was resolved against the saved one-attempt user authorization. The J5-bound Fix11 brief and COMMON are composed at `/Users/vikgamov/.local/state/cueglass/d12-composed/`; the new developer-transition retrospective is `/Users/vikgamov/.local/state/cueglass/state.json.retrospectives/cueglass-fix11-developer-transition-1.md`. Fresh `cue-codex` usage measured 52% weekly headroom. Fix11 trigger detection against this round's worktree changes found no new specialist trigger. Plan authorizes only fix_round 11 under unchanged base/scope/paths; no Fix11 code or acceptance yet. Do not push in this assignment; hand the local candidate to the lead after the local gates.


## Fix11 counterfactual — 2026-10-14

Applied the corrected minimum, paint-order occlusion, NSView Dark rendering and volatile-domain isolation tests before the Dark product refresh. The canonical 03d8df7 scratch copy ran four corrected new oracles plus the permitted revised `quietStudioCompositionPreservesSource`: 5 tests, 18 issues, xcodebuild exit 65. All four new oracles failed; the revised ratio fixture passed. Log: `/Users/vikgamov/.local/state/cueglass/d12-baseline-oracles-confirmed.log`. The XCTest preference plist hash remained `404db95440901be36040ea81b0a39161f2c6935f32b088caee423da614721c7a` across the run. All required local gates now pass; do not push.

## Fix11 local gates — 2026-10-14

- Corrected candidate oracles plus geometry: 5/5 passed.
- Full DebugLocal: 47/47 passed.
- Core14: 14/14 passed.
- Unchanged Q4 probe: checks=700 failures=0 geo=368 geoFailures=0.
- ReleaseLocal build, strict swift-format, beans check, and git diff --check passed.
- XCTest preference plist stayed at SHA-256 404db95440901be36040ea81b0a39161f2c6935f32b088caee423da614721c7a; app preference plist stayed at SHA-256 ae9b093a742a5ff1c5759cfeba6c82c6a6625408b984e6a631b6143be7d17961.
- Independent source/test review and owned-window foreground verification remain pending with the lead. Do not push.
