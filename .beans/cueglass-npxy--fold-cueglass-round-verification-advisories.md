---
# cueglass-npxy
title: Fold CueGlass round verification advisories
status: todo
type: task
created_at: 2026-10-29T00:12:15Z
updated_at: 2026-10-29T00:12:15Z
---

Deferred advisories from the independent review and test of branch feat/first-run-tour-and-cueglass-naming at 5a9dc1b4aadf8870c9646934f005621a0faa0acd. None gate the release.
- [ ] Add a CHANGELOG bullet for the Present vocabulary and fix the stale 'Output' wording in docs/MANUAL_TEST_PLAN.md (lines ~29, 49, 50) and docs/IMPLEMENTATION_STATUS.md (~165)
- [ ] Apply the tester's 25 mutation-proven tour tests (CueFlowTests/TourAcceptanceTests.swift): patch at /Users/vikgamov/.worktrees/cp-reports/cgts2/acceptance-tests.patch, based on 5a9dc1b4aadf8870c9646934f005621a0faa0acd
- [ ] Run the operator-only tour rows T1-T7 on a console session; T4 (Tab, VoiceOver and Esc inside the popover) is the likeliest failure because the buttons are .focusable(false); T1 should include a restored-window launch
- [ ] Remove the deleteLegacySuitePlist shim and unused suite parameter from the tour tests once the stale plists are gone
- [ ] Narrow the production test seam (testingInstallStolenResponder, testingPopoverContentView): make keepSavedResponder internal and test it directly
- [ ] Decide whether end()/keepSavedResponder must also handle makeFirstResponder(nil) leaving the window as first responder (tester F-1; settled by T2/T3)
- [ ] Optional ADR for the PRODUCT_NAME versus module-name split

Added from the tour accessibility round (task cueglass-tour-a11y-fixes, PR #12):
- [ ] Add Help menu commands "Skip Welcome Tour" and "Next Tour Step", enabled only while the tour is active, with no focus change. The popover has no keyboard way to advance or end the tour today (buttons are .focusable(false); Escape in the editor does not end it). Referenced from docs/MANUAL_TEST_PLAN.md T4.
- [ ] Re-anchor test: bind the 8-turn settle wait to an event (anchor rect changed or reanchorPending == false) if it ever flakes; make testingFreshPopoverFrame a method named for the action (for example showAgainForTesting) since reading it re-shows the popover.
- [ ] If the anchor becomes nil or hidden mid-tour, reanchor leaves the old popover up; end or skip the step.
- [ ] Window min height clamps at 660 under AX resize while minSize says 640: check the minSize code path.
- [ ] Operator-only: T4 VoiceOver speech and T6 (two displays, full-screen Space).
- [ ] docs/MANUAL_TEST_PLAN.md T4 status says AXDescription is not set on the tour buttons; raw AX shows AXDescription and AXAttributedDescription both set to the visible labels. Reword.
- [ ] Flaky test: cameraDockFailedFirstOpenPreservesRunningFloatingSurface (OperatorFeatureTests.swift:3400) failed once on a full native run because UserDefaults.standard cameraDockPreferences held a stale 314-byte catalog; isolate that test's defaults.
- [ ] Commit this bean (and the other untracked beans in the shared checkout) so docs/MANUAL_TEST_PLAN.md T4 can cite it.
