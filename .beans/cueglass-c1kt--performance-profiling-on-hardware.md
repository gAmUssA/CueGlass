---
# cueglass-c1kt
title: Performance profiling on hardware
status: in-progress
type: task
priority: normal
tags:
    - hardware
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T22:52:47Z
parent: cueglass-aeqt
---

Pending profiling on real hardware with Release builds. Record OS, machine, refresh rates, fixture size, timing and layout spikes. Never fabricate numbers.

## Checklist

- [ ] 100,000-word generated script: bounded per-frame work, no whole-document rebuild loop
- [ ] Steady-state frame callback against the < 2 ms goal (goal, not guarantee)
- [ ] 60-minute session: no progressive memory growth or accumulating timing error
- [ ] Repeated pause/close cycles: display links and windows released; paused state not busy

Local Mac and Release build are available. Begin measured profiling preparation now, then launch only after current tester and reviewer release native focus. Use actual 100k-word document and real 60-minute session, preserving raw measurements; no injected-clock substitution, privacy changes, or invented callback metrics. Existing physical/optical and signed cloud exceptions remain separate.
