---
# cueglass-sx4d
title: 'Spike: run CueGlass under the Mac App Sandbox and list entitlements'
status: in-progress
type: task
priority: high
created_at: 2026-11-03T03:37:20Z
updated_at: 2026-11-03T03:47:52Z
parent: cueglass-gzi5
---

Mac App Store builds require the app sandbox. Verify document open/save, Camera Dock camera, microphone and speech recognition, and the Follow Voice path under the sandbox. List the needed entitlements, then write an ADR.

- [ ] Build with sandbox on and exercise the manual test plan rows that touch files, camera, microphone, speech
- [x] List entitlements and any feature that cannot work sandboxed
- [x] Write the ADR (docs/adr)
- [x] Feed the result into cueglass-pili

## Findings (2026-11-03)

Local configurations are already sandboxed; the sandboxed DebugLocal build launched and opened .txt/.rtf with no sandbox denials. Proposed set recorded in ADR 0015 (proposed): app-sandbox, files.user-selected.read-write, device.audio-input. Camera Dock does not capture the camera.

First item stays open: panel, Finder double-click of .cueflow, Save, autosave and Versions, Save a Copy, microphone prompt, speech model download and Follow Voice were NOT RUN (headless session, no screen capture or UI input). They need the owner on the hardware; the list is ADR 0015 Consequences items 1-5. Complete this bean once those pass.
