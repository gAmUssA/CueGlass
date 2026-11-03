---
# cueglass-sx4d
title: 'Spike: run CueGlass under the Mac App Sandbox and list entitlements'
status: todo
type: task
priority: high
created_at: 2026-11-03T03:37:20Z
updated_at: 2026-11-03T03:37:20Z
parent: cueglass-2ur9
---

Mac App Store builds require the app sandbox. Verify document open/save, Camera Dock camera, microphone and speech recognition, and the Follow Voice path under the sandbox. List the needed entitlements, then write an ADR.

- [ ] Build with sandbox on and exercise the manual test plan rows that touch files, camera, microphone, speech
- [ ] List entitlements and any feature that cannot work sandboxed
- [ ] Write the ADR (docs/adr)
- [ ] Feed the result into cueglass-pili
