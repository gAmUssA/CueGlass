---
# cueglass-c1kt
title: Performance profiling on hardware
status: todo
type: task
tags:
    - hardware
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T18:53:52Z
parent: cueglass-aeqt
---

Pending profiling on real hardware with Release builds. Record OS, machine, refresh rates, fixture size, timing and layout spikes. Never fabricate numbers.

## Checklist

- [ ] 100,000-word generated script: bounded per-frame work, no whole-document rebuild loop
- [ ] Steady-state frame callback against the < 2 ms goal (goal, not guarantee)
- [ ] 60-minute session: no progressive memory growth or accumulating timing error
- [ ] Repeated pause/close cycles: display links and windows released; paused state not busy
