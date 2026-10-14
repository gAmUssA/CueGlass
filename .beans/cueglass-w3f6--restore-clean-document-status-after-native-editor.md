---
# cueglass-w3f6
title: Restore clean-document status after native editor Undo
status: completed
type: bug
priority: normal
created_at: 2026-10-14T09:43:21Z
updated_at: 2026-10-14T11:28:20Z
parent: cueglass-aeqt
---

After a live native editor edit followed by Cmd-Z, the source returned exactly to its original text but the untitled document still displayed Edited. Evidence: /Users/vikgamov/.local/state/cueglass/d12-lead-keyboard.md. Reproduce on a clean local document; balance NSDocument change tracking through editor Undo/Redo; add a regression proving source, attributed content, and clean-document status return to baseline without saving; rerun native and relevant core gates.


## Checklist

- [x] Reproduce the native editor's stale Edited state after undo.
- [x] Share the document undo manager with the editor window and balance document change counts across top-level edit, undo, and redo groups.
- [x] Add a regression covering grouped attributed edits, Undo → Redo → Undo, and clean status without saving.
- [x] Pass the full DebugLocal native suite (48 tests), strict Swift formatting, and ReleaseLocal build.

## Summary of Changes

The main window now returns the document's undo manager. Undoable source/style/speed updates rely on balanced undo-group accounting, while the editor observer applies change-undone/redone counts and updates the mirrored attributed source. The regression confirms three grouped insertions return both source and document status to their original clean state after Undo, Redo, and a second Undo.
