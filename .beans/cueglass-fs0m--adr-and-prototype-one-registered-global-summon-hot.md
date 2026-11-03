---
# cueglass-fs0m
title: 'ADR and prototype: one registered global summon hotkey without a global event monitor'
status: todo
type: feature
priority: normal
created_at: 2026-11-03T02:22:20Z
updated_at: 2026-11-03T02:22:30Z
parent: cueglass-2ur9
---

CueNotch Command-Shift-Space, NotchPrompter opt-in global shortcuts, Notchie global Shift+arrows let a presenter control the prompter while another app is frontmost. ADR 0005 forbids a global event monitor; a registered hotkey (Carbon RegisterEventHotKey) is a different mechanism but the ADR must say so. Opt-in, off by default, requires a modifier, keys never taken from text fields. M. Blocked on operator question 5. Source: advisor rank 2, investigator rank 4.
