---
# cueglass-p8en
title: 'AGENTS.md: document a source build that works on Intel Macs'
status: todo
type: task
priority: normal
created_at: 2026-11-03T05:51:53Z
updated_at: 2026-11-03T05:51:53Z
parent: cueglass-qe15
---

Copilot review on PR 17 (README.md:16): the README says the universal app supports Apple silicon and Intel Macs and sends readers to AGENTS.md to build from source, but the documented build command uses -destination 'platform=macOS,arch=arm64' and DebugLocal sets ONLY_ACTIVE_ARCH=YES, so it builds Apple silicon only.

- [ ] Add a host-native or universal (arm64 x86_64) source build command to AGENTS.md, or reword the README claim
- [ ] Check the command from a clean checkout
- [ ] Add a CHANGELOG line if user-visible
