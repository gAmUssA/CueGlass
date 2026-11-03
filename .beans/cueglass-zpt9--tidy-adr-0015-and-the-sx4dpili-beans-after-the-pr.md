---
# cueglass-zpt9
title: Tidy ADR 0015 and the sx4d/pili beans after the PR 19 reviews
status: todo
type: task
priority: normal
created_at: 2026-11-03T14:21:51Z
updated_at: 2026-11-03T14:21:51Z
parent: cueglass-gzi5
---

Advisories deferred from the reviews of PR 19 (ADR 0015 sandbox spike). None changes the proposed entitlement set.

- [ ] Copilot (thread on .beans/cueglass-sx4d, line 23): the sx4d completion gate lists ADR Consequences items 1-5, but item 5 (a distribution-signed archive passes App Store Connect validation) needs the signing work in cueglass-pili, and pili is blocked_by sx4d. Limit sx4d's gate to hardware items 1-4 and leave item 5 with pili, or drop the blocked_by.
- [ ] Reviewer: ADR 0015 cites docs/ICLOUD_SETUP.md steps 1 and 2 for 'gitignored'; step 3 is the step that says it. Move the adjective onto step 3.
- [ ] Tester: ADR 0015 says the CueFlow target creates no security-scoped bookmarks (true), but does not mention that CueFlow/Import/ScriptImporter.swift:21-22 calls startAccessingSecurityScopedResource on user-selected URLs; mention it.
- [ ] Hardware rows 1-5 of ADR 0015 Consequences remain the owner's; this bean does not cover them.
