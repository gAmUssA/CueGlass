---
# cueglass-v6py
title: Prototype opt-in Camera Dock for MacBook notch displays
status: scrapped
type: feature
priority: high
created_at: 2026-10-16T07:22:39Z
updated_at: 2026-10-16T10:55:21Z
parent: cueglass-aeqt
---

Implement and independently verify an opt-in AppKit Camera Dock prompter surface positioned below MacBook camera-housing geometry, with a top-center fallback. Preserve the macOS 14 deployment target and the existing shared PlaybackSession, playback controls, privacy behavior, and regular display surfaces. See the accepted Camera Dock research/UX decision and branch feat/cueglass-camera-dock.

- [x] Implement safe-area-aware placement, fallback, surface switching, and repeat-open idempotence.
- [x] Add deterministic geometry, playback-anchor, display lifecycle, session restoration, keyboard/accessibility, and input-boundary coverage.
- [x] Update implementation/design and manual-acceptance documentation.
- [x] Run developer build, tests, formatting, Beans consistency, and diff checks on the pushed tip.
- [ ] Complete independent full review and test against the exact pushed tip.
- [ ] Verify macOS 14 compile compatibility and current acceptance criteria independently.
- [ ] Complete direct M1–M12 checks on a notched MacBook and a macOS 14 runtime; synthetic tests and deployment-target builds do not count for these rows.

No signing, notarization, merge, or release is part of this prototype work.


## Independent review and test follow-up

- [ ] Put Camera Dock Close, Play/Pause, and Adjust controls in the panel key-view loop; keep the assertion that Tab traversal reaches a control.
- [ ] Preserve the Camera Dock disconnect message through the production screen-change callback; retain the take and anchor, with no automatic fallback.
- [ ] Keep preferences-read, no-display, fit, and placement-recovery notices visible through the shared status-refresh path.
- [ ] Add the reversed but individually valid auxiliary-area geometry case.
- [ ] Complete the reported integration assertions: Preview menu/shortcut route, exact Timed Scrolling end-target preservation, Floating-equivalent Follow Voice line/session/silence-hold behavior, remaining mapped keys and numeric-field editing, accessibility tree/actions, and disabled no-document controls.
- [ ] Replace wall-clock polling in the Follow Voice Camera Dock integration test with deterministic completion signaling.
- [ ] Update implementation-status test counts after the new tests land.
- [ ] Pass a fresh independent review and test run on the corrected pushed tip.



## Reasons for Scrapping

This was a duplicate Bean created in the shared main checkout after the existing feature Bean was not visible there. Continue tracking Camera Dock work in the existing feature Bean `cueglass-jjwt` in the feature worktree; its accepted scope and history are authoritative.
