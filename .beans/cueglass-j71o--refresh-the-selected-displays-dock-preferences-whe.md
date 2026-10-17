---
# cueglass-j71o
title: Refresh the selected display's Dock preferences when live Dock closes
status: completed
type: bug
priority: high
created_at: 2026-10-17T15:06:54Z
updated_at: 2026-10-17T19:55:25Z
parent: cueglass-aeqt
---

B3 from the independent final3 review: if Camera Dock is active on display A, the user changes the inspector's selected display to B, then exits Dock, refresh the inspector from B before accepting further edits. Current behavior can leave A's width/line/nudge values visible and save them into B after a nudge. Preserve the intended live Dock target while it is open; fix only the return-to-inspector preference target transition. Add a deterministic regression: A custom values, Dock live on A, select B, exit, edit B nudge, verify A unchanged and B's prior width/lines/island preference preserved. Exact source and independent probe evidence: /Users/vikgamov/.local/state/cueglass/release-030/final3/reviewer.md (B3), reviewer-transition-probe.swift/.log. This is follow-up after the active cueglass-nj97 correction. Must be verified on a new exact pushed tip before release.

- [x] Refresh inspector preferences on every Camera Dock teardown path after the live Dock reference is cleared.
- [x] Add a regression for live Dock on A, selecting B, closing, editing B, and confirming both display catalogs retain independent settings.
- [x] Run the complete native suite (163 tests), strict Swift formatting, and diff checks.
- [x] Commit and push the fix, then obtain independent exact-tip review and test verification before release. Commits f827d07ace52c5afe1bb6ade3d6704dafc2ce2c3 (window close) and 740db33 (Output/Floating replacement) on release/cueglass-030; independent final6 and final7 reviews (final7 review 5559397563 at e021d43) record B3 and N1 as resolved; PR #5 CI 39057584583 success.

- [x] Refresh the selected display after a live Dock is replaced by Output or Floating (surface picker, View menu, toolbar, Present on another display), clearing the stale reference on the no-screen Floating return (N1 from the final5 review).
- [x] Add regressions for Output, Floating and Present-on-B replacing a live Dock on A, editing B afterward, and confirming both catalogs keep independent settings.

## Replacement paths — 2026-10-17

Independent final5 review (N1) found that Display Output and Floating replacing a live Dock, from the surface picker, the View menu, the toolbar, or Present on another display, left the previous display's values in the inspector. `showOutput` and `showFloating` now reload the selected display's preferences once the live Dock reference is cleared, and the no-screen Floating return clears the stale reference first. `presentOnDisplay` gained a key-based entry so the menu path can be exercised without a modal confirmation. Three new regressions (Output, Floating, Present on B) fail on the prior source with B still showing 520/4/24/island off and pass after the change; the window-close regression keeps passing. An open Dock is not moved by picker changes, and a successful Output return is unchanged.

## Summary of Changes

Every Camera Dock teardown and replacement path (window close, display loss, invalid placement, Output, Floating, Present on another display) reloads the selected display's Dock preferences once the live Dock reference is cleared, so edits after the Dock closes persist to the display the picker shows. Regressions for each path fail on the prior source and pass after. Shipped in PR #5 (merge 80d23b81f641164eeaff695169e791637cb9db93) and released as v0.3.0 (run 39061330997). An open Dock is still not moved by picker changes (ADR 0012).
