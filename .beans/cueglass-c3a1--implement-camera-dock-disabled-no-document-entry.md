---
# cueglass-c3a1
title: Implement Camera Dock disabled no-document entry
status: completed
type: task
priority: normal
created_at: 2026-10-16T12:42:03Z
updated_at: 2026-10-16T13:55:39Z
---

Apply the accepted B2 ruling on feat/cueglass-camera-dock from 6bbba203661bc8c2a28d7cf40184aad1457a54e7: disable only View > Camera Dock when AppDelegate.current is nil and add regression coverage for disabled/no-document, enabled/current-controller, no picker, and no active surface. Preserve sibling menu behavior and existing command routing.


## Checklist

- [x] Inspect AppDelegate menu construction and accepted B2 constraints on the task worktree.
- [x] Disable only View > Camera Dock when no OperatorWindowController is current; leave every sibling menu item unchanged.
- [x] Extend native regression coverage for disabled/enabled state, no picker/document creation, and no active presentation surface while retaining the nil-controller route assertion.
- [x] Run the repository-required gates, commit and push the bounded fix, and verify the pushed tip and clean worktree.

## Summary of Changes\n\nView > Camera Dock now validates enabled only when a current operator controller exists, with sibling menu behavior unchanged. Regression coverage verifies enabled and disabled states, no document creation or presentation owner without a document, and retained nil-controller shortcut routing. Commit 95f61f8699690836898f7e99fd844fd6d920fe8f was pushed. Core (86), native (121), direct-runner (121), formatting, Beans, DebugLocal and universal ReleaseLocal checks pass. Fresh independent review/test plus remote CI remain acceptance gates for the broader Camera Dock feature.
