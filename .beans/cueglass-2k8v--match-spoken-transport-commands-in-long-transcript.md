---
# cueglass-2k8v
title: Match spoken transport commands in long transcript hypotheses
status: todo
type: bug
created_at: 2026-10-16T04:03:33Z
updated_at: 2026-10-16T04:03:33Z
parent: cueglass-2mil
---

Copilot identified a medium-severity edge case while reviewing the v0.2.0 release: the command matcher and speech adapter truncate recognized hypotheses to the last four words before searching. A finalized utterance such as “Cue Glass stop take please” can lose its wake phrase, and cumulative revisions can erase an unchanged pending command. Scan complete incoming hypotheses with a bounded sliding window before trimming retained history, remove premature adapter truncation, and add deterministic tests for long results, both recognition channels, and cumulative pending candidates.
