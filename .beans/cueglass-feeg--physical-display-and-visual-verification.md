---
# cueglass-feeg
title: Physical display and visual verification
status: todo
type: task
priority: normal
tags:
    - hardware
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-17T19:58:52Z
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
- [ ] Floating window (R10) over a full-screen video-call app: stays visible, opacity applies, Escape and control panel regain control from click-through
- [ ] Clicker / foot-pedal default keys (R14) drive playback when an app window is key
- [ ] Scrub with trackpad/wheel (R13): pauses, no momentum after Play

## Carried from the 0.3.0 release — 2026-10-17

The owner accepted three r11 observations on the notched MacBook (notch attachment and animation, the editor-adjacent preview, microphone selection and switching), recorded in docs/MANUAL_TEST_PLAN.md. Everything below was not observed and moves here from the shipped 0.3.0 Beans; the manual plan rows are the pass criteria.

- [ ] Camera Dock hardware rows M1–M14, M17 and M18 on a notched MacBook and on displays without a notch (from cueglass-jjwt, cueglass-wky0, cueglass-f01c)
- [ ] M15 remainder: text and control clearance below the housing band, centred reading line, dimmed neighbours and edge fades, expanded tray shape and prompt readability (from cueglass-tgvc)
- [ ] M16 remainder: Collapse to Notch, hover peek, in-band control placement, Space reopen, Reduce Motion (from cueglass-tgvc)
- [ ] M13 placement-map agreement with the live Dock on notched, no-inset and external displays (from cueglass-tgvc)
- [ ] Microphone rows: hot-plug recovery, relaunch memory, the not-connected wording and catch-up feel with an external microphone (from cueglass-6nk0, cueglass-f01c)
- [ ] M12 macOS 14 runtime: launch, Camera Dock, Follow Voice gating and the Quiet Studio window on a Mac running macOS 14 (from cueglass-f01c, cueglass-jjwt, cueglass-7bw1)
- [ ] Quiet Studio visual and accessibility review on hardware: Dark appearance, VoiceOver, key-window and menu behavior in an unlocked session (from cueglass-7bw1)
- [ ] Compare the shipped 0.3.0 build against docs/design/quiet-studio-concept.svg: toolbar, take bar, notices, Controls panel (from cueglass-qzoj)
- [ ] Controls panel and toolbar retest on the notched MacBook (from cueglass-trhd)
