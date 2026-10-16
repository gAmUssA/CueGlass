---
# cueglass-qnw5
title: Stabilize display reconnect regression in full native suite
status: completed
type: task
priority: normal
created_at: 2026-10-15T20:15:06Z
updated_at: 2026-10-15T20:20:15Z
parent: cueglass-aeqt
---

The current full DebugLocal app suite fails OperatorFeatureTests.displaySelectionRemapsWhenDisplayIDChanges with selectedDisplay remaining disconnected instead of the reconnected fake display key. The same test passes in isolation. Find and fix the suite-order or test-environment cause without weakening the product expectation; full native suite and isolated regression must both pass.

## Summary of Changes

Seed the controller display mapping with the synthetic display before simulating disconnect/reconnect, so a persisted preference cannot shadow the test selection. Added a disabled “No display connected” Output picker placeholder to keep SwiftUI selection valid when no displays are present. Verified the isolated regression and full DebugLocal native suite: 82 tests passed.
