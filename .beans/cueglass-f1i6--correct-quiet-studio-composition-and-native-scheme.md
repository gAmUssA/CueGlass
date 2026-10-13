---
# cueglass-f1i6
title: Correct Quiet Studio composition and native scheme runner
status: in-progress
type: task
priority: high
created_at: 2026-10-13T21:21:08Z
updated_at: 2026-10-13T21:45:29Z
parent: cueglass-aeqt
---

Complete cumulative fix3 from the source-checked visual correction plan. Preserve R01–R16, authored source and shared timeline. Track developer work separately from independent visual acceptance.

- [x] Adopt reviewed sandbox corrections and balance actual native panes
- [x] Complete inspector, paragraph gutter, locked editing and HUD/grip details
- [x] Apply unhosted app-dylib scheme remedy and run all native tests
- [x] Inspect Ready/Paused light/dark actual-launch evidence at three sizes
- [ ] Run core/release/format/Beans/supplemental gates, update docs, commit and push
- [ ] Write d4 report with full SHA and residual limits

Developer evidence: 19 native tests pass through the normal DebugLocal scheme; 14 core tests pass. Composite and direct per-view caches inspected with key=false and WindowServer limitations retained. Exact geometry probe comparisons revealed only 4e-13 pt floating error; a documented 1e-9 pt tolerance plus exact session/logical-size assertion passes all 39 outcomes. Native paused preview clip position is reapplied after scaling and tested. Full independent visual acceptance remains open.
