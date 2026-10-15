---
# cueglass-r9mj
title: Adapt Follow Voice glide pace to presenter cadence
status: in-progress
type: task
priority: normal
created_at: 2026-10-15T18:18:42Z
updated_at: 2026-10-15T20:22:40Z
parent: cueglass-2mil
---

Estimate the presenter's delivery cadence from confirmed script-following advances and modestly accelerate the shared playback glide when speech is faster than the configured baseline. Keep the estimate bounded, smoothed, and inactive for ad-libs, volatile updates, pauses, jumps, or manual overrides. Add deterministic estimator and playback-drive tests; document user-visible behavior and manual validation.


## Acceptance

- [x] Estimate cadence only from finalized, on-script advances and adapt the shared glide smoothly.
- [x] Keep pace at or above the configured baseline, cap increases at 40%, and ease toward baseline after a long pause.
- [x] Add deterministic estimator and playback-drive tests; update inspector help and manual verification steps.
- [x] Confirm adaptive pace increases with faster human delivery on macOS 26+ (operator confirmed 2026-10-15).
- [ ] Confirm slower delivery and silence ease back toward the configured baseline, and ad-libs/jumps/manual overrides do not create a speed burst.


## Verification (2026-10-15)

- Core pace estimator tests and the app-linked faster-cadence/volatile-cadence tests passed.
- DebugLocal app build targets macOS 14.
- Human faster/slower speech verification remains pending on macOS 26+.


## Operator feedback (2026-10-15)

The operator reports the adaptive pace adjustment works in the current app. The full faster/slower cadence and silence-recovery matrix remains open.

## Human verification (2026-10-15)

The operator confirmed the adaptive pace adjustment works. The faster/slower baseline, silence recovery, ad-lib, skip/reread, and manual-override matrix remains open.
