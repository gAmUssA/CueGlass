---
# cueglass-6nk0
title: Keep Follow Voice capturing across microphone changes and make following more reactive
status: in-progress
type: bug
priority: high
created_at: 2026-10-17T03:34:37Z
updated_at: 2026-10-17T03:34:37Z
---

Owner reports Follow Voice misbehaves with multiple microphones: using an external microphone on the notched MacBook, the app appears to lose access to the microphone, and following feels sluggish. Diagnose the capture path (AVAudioEngine default input, configuration-change handling, device selection) and the alignment latency, fix capture continuity across device changes, add an explicit microphone choice, and tune reactiveness. Keep the shared timeline, manual-priority, and spoken-command contracts (ADRs 0007-0011).

## Work checklist

- [x] Diagnose: configuration-change notifications ended the session; cadence-capped glide trailed confirmed speech.
- [x] Recover capture in place on configuration changes (new tap, same analyzer and stream); retry a not-ready input format; raise input buffering.
- [x] Microphone picker in the inspector, remembered by UID, with fallback to the system default and live switching.
- [x] Catch-up glide for confirmed progress inside the configured maximum; volatile wording unchanged.
- [x] Core and native tests for the arithmetic, selection, fallback, source hand-off, and far-ahead glide.
- [ ] Owner retest on the notched MacBook with the external microphone (manual plan rows: hot-plug, picker, catch-up).
