---
# cueglass-feeg
title: Physical display and visual verification
status: todo
type: task
tags:
    - hardware
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-13T18:53:52Z
parent: cueglass-aeqt
---

Pending hardware. Automated tests and a display link do not prove these.

## Checklist

- [ ] Very slow scrolling (1–5 pt/s) on 1x and 2x displays: no persistent visible stepping; decide the fractional-translation strategy from evidence
- [ ] Mixed-refresh output vs preview: stable reading speed and aligned content
- [ ] Negative desktop origin and mixed backing scales: correct output placement
- [ ] Display disconnect and sleep: safe pause at retained position, no catch-up leap
- [ ] Hidden or minimized operator window: external presentation continues
- [ ] Output window level vs menu bar with separate Spaces
- [ ] All four reflection combinations through the intended optical setup using the calibration fixture
- [ ] Editor Space/arrows edit text and never trigger transport
