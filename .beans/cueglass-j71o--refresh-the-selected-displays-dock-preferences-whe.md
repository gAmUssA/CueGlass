---
# cueglass-j71o
title: Refresh the selected display's Dock preferences when live Dock closes
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T15:06:54Z
updated_at: 2026-10-17T16:24:32Z
parent: cueglass-aeqt
---

B3 from the independent final3 review: if Camera Dock is active on display A, the user changes the inspector's selected display to B, then exits Dock, refresh the inspector from B before accepting further edits. Current behavior can leave A's width/line/nudge values visible and save them into B after a nudge. Preserve the intended live Dock target while it is open; fix only the return-to-inspector preference target transition. Add a deterministic regression: A custom values, Dock live on A, select B, exit, edit B nudge, verify A unchanged and B's prior width/lines/island preference preserved. Exact source and independent probe evidence: /Users/vikgamov/.local/state/cueglass/release-030/final3/reviewer.md (B3), reviewer-transition-probe.swift/.log. This is follow-up after the active cueglass-nj97 correction. Must be verified on a new exact pushed tip before release.

- [x] Refresh inspector preferences on every Camera Dock teardown path after the live Dock reference is cleared.
- [x] Add a regression for live Dock on A, selecting B, closing, editing B, and confirming both display catalogs retain independent settings.
- [x] Run the complete native suite (163 tests), strict Swift formatting, and diff checks.
- [ ] Commit and push the fix, then obtain independent exact-tip review and test verification before release.
