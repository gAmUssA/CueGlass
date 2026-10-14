---
# cueglass-ykl0
title: Owner iCloud setup and two-Mac verification
status: todo
type: task
priority: normal
tags:
    - owner
    - hardware
created_at: 2026-10-13T18:53:52Z
updated_at: 2026-10-14T13:34:22Z
parent: cueglass-ffq6
blocked_by:
    - cueglass-pili
---

Pending owner action and hardware. Cannot be completed by agents.

Blocked on owner-supplied signing team, real bundle identifier and iCloud container identifier (`Configuration/Owner.xcconfig`, from `Owner.xcconfig.example`), an iCloud account, and a second Mac. See ADR 0003.

## Checklist

- [ ] Owner fills `Owner.xcconfig` (team, bundle ID, container ID) and the per-config iCloud Info.plist container key
- [ ] Build `DebugICloud` with signing; record the exact command and result
- [ ] Verify `NSUbiquitousContainers` / entitlements resolve to the real container
- [ ] Save on Mac A, open on Mac B: content and saved reading style transfer after actual sync
- [ ] Both Macs edit offline: conflict recovery preserves recoverable work; record whether NSDocument shows a conflict chooser on macOS 27
- [ ] Cloud change during a running take: take unchanged until explicit paused reload
- [ ] Cloud-only (not downloaded) file and iCloud unavailable / account change: honest status, no data loss
