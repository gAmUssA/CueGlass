---
# cueglass-w3f6
title: Restore clean-document status after native editor Undo
status: todo
type: bug
created_at: 2026-10-14T09:43:21Z
updated_at: 2026-10-14T09:43:21Z
parent: cueglass-aeqt
---

After a live native editor edit followed by Cmd-Z, the source returned exactly to its original text but the untitled document still displayed Edited. Evidence: /Users/vikgamov/.local/state/cueglass/d12-lead-keyboard.md. Reproduce on a clean local document; balance NSDocument change tracking through editor Undo/Redo; add a regression proving source, attributed content, and clean-document status return to baseline without saving; rerun native and relevant core gates.
