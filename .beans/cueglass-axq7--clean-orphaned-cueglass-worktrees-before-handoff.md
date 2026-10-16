---
# cueglass-axq7
title: Clean orphaned CueGlass worktrees before handoff
status: completed
type: task
priority: normal
created_at: 2026-10-14T17:02:39Z
updated_at: 2026-10-16T04:16:57Z
---

Remove only verified clean review worktrees whose commits are already contained in origin/main. Preserve all operator worktrees and unrelated root-checkout edits.

- [x] Verify the four candidate worktrees are clean and contained in origin/main
- [x] Remove the four worktrees and delete their local branches
- [x] Leave dirty and unmerged operator worktrees untouched
- [x] Stash the two unrelated root-checkout Bean edits for handoff

## Summary of Changes

- Removed four verified clean worktrees and their local branches.
- Left the dirty `cueglass-lead-progress` and `cueglass-native` worktrees, plus unmerged `cueglass-tracking` and `cueglass-voice-prototype`, untouched.
- Stashed the two unrelated root-checkout Bean edits as `preserve unrelated CueGlass Bean edits for handoff`.

## Additional post-release cleanup

- [x] Verify the nine speech-follow review/test worktrees are clean and their branches are contained in `origin/main`.
- [x] Remove the nine verified worktrees and delete their local branches.
- [x] Preserve the dirty Follow Voice, lead-progress, and native worktrees and the unmerged tracking and voice-prototype worktrees.

## Additional Summary of Changes

Removed nine clean speech-follow review/test worktrees whose branch tips were already contained in `origin/main`, then deleted their local branches. Left the dirty Follow Voice, lead-progress, and native worktrees and the clean but unmerged tracking and voice-prototype worktrees untouched.
