---
# cueglass-feld
title: Compare notch prompter competitor previews and UX
status: completed
type: task
priority: normal
created_at: 2026-10-16T12:56:07Z
updated_at: 2026-10-16T13:09:23Z
parent: cueglass-aeqt
---

Research the notch preview and camera-side prompting experiences at https://www.notchscript.com/, https://notchprompter.com/, and https://notchie.app/. Use first-party product pages, public source where available, and macOS/Axiom research to distinguish documented behavior from inferred implementation. Produce a sourced comparison of how each previews and positions the prompter, reveal/expand interactions, screen-capture behavior and limitations, and native implementation details that can be verified. Have the UX/design seat recommend a polished CueGlass preview/entry flow with concrete states and acceptance criteria. Keep this research-only: do not modify app code or release anything.\n\n- [x] Research product claims and source/code evidence for all three apps\n- [x] Produce macOS/Axiom implementation findings and confidence levels\n- [x] Produce comparative UX flow recommendation and acceptance criteria\n- [x] Review reports, record evidence, and summarize findings

## Summary of Changes

- Compared NotchScript, the actual NotchPrompter product at jpomykala/NotchPrompter, and Notchie, while separately labeling Dronnn/notchTelePrompt as an unrelated namesake.
- Documented source-verified AppKit geometry and window behavior, Apple’s screen-capture limitations, and vendor-only claims with confidence labels.
- Recommended a staged Camera Dock preview with a placement map, paused Ready state, non-modal first-use callout, and testable acceptance criteria.
- No app code changed; hardware and screen-capture behavior remain untested.
