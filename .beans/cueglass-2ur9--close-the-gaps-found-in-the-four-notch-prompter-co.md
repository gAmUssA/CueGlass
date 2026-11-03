---
# cueglass-2ur9
title: Close the gaps found in the four notch-prompter competitors
status: todo
type: epic
priority: high
created_at: 2026-11-03T02:22:30Z
updated_at: 2026-11-03T03:37:20Z
---

Research task cueglass-competitor-research (2026-11-03) compared CueNotch, Notchie, NotchPrompter and Notch (notchscript.com) with CueGlass 0.3.x. Reports live in the operator's cp-reports dir, not the repo: /Users/vikgamov/.worktrees/cp-reports/cr1/report-advisor.md and /Users/vikgamov/.worktrees/cp-reports/cr1/report-investigator.md.

## Findings that drive the plan
- Install trust is the largest gap: all four install without a Gatekeeper warning (CueNotch and NotchPrompter via the Mac App Store, Notchie via App Store, Setapp and direct ZIP, Notch direct with a license key). CueGlass ships an unsigned prerelease. Bean cueglass-pili owns signing.
- Voice following works on macOS 14 in all four (NotchPrompter and probably Notchie by loudness gate only; CueNotch matches words). CueGlass Follow Voice needs macOS 26.
- Screen-share exclusion is the marketed headline of three of the four. Apple documents NSWindow.SharingType.none as legacy and not for hiding content from capture, so copying the claim would be false. CueGlass discloses that the prompt can appear in recordings (ADR 0012).
- Summoning the prompter while another app is frontmost: CueNotch Command-Shift-Space, NotchPrompter opt-in global shortcuts, Notchie global Shift+arrows. ADR 0005 forbids a global event monitor.
- CueNotch only: PPTX, PDF, DOCX and Markdown import with slide notes, script folders, and an AI preparation suite (rewrite, rehearsal camera, memorize, live captions) behind a Pro tier and an account.

## Business picture
NotchPrompter 4.99 USD on the App Store plus a free source-available non-commercial build. Notchie 29.99 USD once (also Setapp, 5-minute demo). Notch 29.99 USD once with a free trial. CueNotch 29.99 USD lifetime or 7.99 USD per week, with a capped free tier. CueGlass is free, public source, no account, no caps.

## Plan
- Phase 0, days, no ADR: README states the Follow Voice floor; license and positioning decision; screenshots and a one-page site.
- Phase 1, distribution: signed and notarized build (cueglass-pili).
- Phase 2, call presenter: capture-exclusion spike then decision; one registered global summon under a new ADR amending 0005; hover hold.
- Phase 3, reach: macOS 14 voice scope decision; office and speaker-notes import; script library; localization; accessible font preset.
- Deferred, operator scope: AI preparation suite, accounts, subscription, phone remote.

## Protect
Honest capture disclosure, no account or upload, NSDocument model, lines-per-minute pace, one session across four surfaces, Camera Dock contract, app-local keys, free with no caps.

## Operator questions
1. Next user: Zoom presenter or stage talk? 2. Stay free? 3. macOS 14 speech in scope? 4. Hover hold? 5. One registered global hotkey under a new ADR? 6. Import before call features?

- [x] Operator answers the six questions
- [ ] Phase 0 beans done
- [ ] Phase 1 done (cueglass-pili)
- [ ] Phase 2 beans done
- [ ] Phase 3 beans decided or done
