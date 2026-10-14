---
# cueglass-lw2i
title: Preserve anchors and running state after chunked measurement
status: in-progress
type: bug
priority: high
created_at: 2026-10-13T23:11:38Z
updated_at: 2026-10-14T00:04:19Z
parent: cueglass-aeqt
---

Independent broad review r4 at4eef1df establishes two mandatory-contract failures: R4-1 near-end font64→120 restoration clamps to obsolete end (offset7990→2490); R4-2 asynchronous surface resume replays countdown while synchronous short-script path stays running. Both concern measurement completion ordering. Same cueglass-v1 originalbase13bd9b6 and cumulativefix5; no automaticfix6. Existing allowance exhausted: require assessed investigator and pinned judge diagnosis before code correction.

## Acceptance

- [x] Preserve independent reproductions and long/short discriminator
- [x] Investigate cause and test a discriminating counterfactual without canonical source edits
- [x] Record bounded diagnosis under original task/base/count
- [ ] Correct anchor and resume intent while preserving cancellation, source, snapshot, LPM and single clock
- [ ] Add meaningful long-script asynchronous regressions and pass normal full suite
- [ ] Independent final-tip whole-branch verification, including native checks when GUI available
