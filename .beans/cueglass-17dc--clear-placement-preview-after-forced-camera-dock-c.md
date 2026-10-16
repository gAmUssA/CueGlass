---
# cueglass-17dc
title: Clear placement preview after forced Camera Dock close
status: completed
type: bug
priority: high
created_at: 2026-10-16T16:20:05Z
updated_at: 2026-10-16T16:32:10Z
parent: cueglass-wky0
---

Review blocker on cueglass-wky0 at 8896f51897b8efcc17d1407a7860c91fa948d16c. Display disconnect, invalid placement, and a forced Camera Dock panel close clear the dock but only refresh the editor, leaving the opaque placement map and CAMERA DOCK caption over the script preview. Recompute preview state after the dock is cleared: with placement disclosure collapsed, restore script preview, caption, and aspect; with it expanded, show a map from the current valid target or hide it if no layout exists. Preserve the current pause, retained anchor, and status messages. Add deterministic native regression coverage for disconnect and invalid placement, including collapsed/expanded behavior where practical. Fold the accepted advisory into ADR 0012 and the parent Bean: name M1–M14 as pending owner gates and reconcile the detached 6 pt geometry. Do not sign, notarize, or release.

## Summary of Changes

- Forced Camera Dock teardown now restores the saved preview size and anchor, pauses with the existing status, and recomputes map visibility, caption, and aspect. Invalid placement continues the active render pass rather than nesting another render.
- Disconnect, invalid-layout, and forced panel-close regressions cover collapsed and expanded disclosure behavior, persistent status, retained pause/anchor, normal preview geometry, and maps from a valid target.
- ADR 0012 now records the detached 6 pt gap and leaves all M1–M14 owner checks pending. Core 89 tests, native 127 tests, strict Swift formatting, and a clean unsigned DebugLocal arm64 build targeting macOS 14 passed.
