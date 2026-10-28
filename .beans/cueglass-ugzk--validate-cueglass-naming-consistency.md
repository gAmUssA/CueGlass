---
# cueglass-ugzk
title: Validate CueGlass naming consistency
status: in-progress
type: task
created_at: 2026-10-28T16:53:39Z
updated_at: 2026-10-28T16:53:39Z
---

Product is CueGlass; Xcode project/scheme/module keep internal CueFlow name (AGENTS.md). Validate user-visible strings, menus, About, docs, README, bundle display name use CueGlass.
- [x] Inventory user-visible CueFlow occurrences
- [x] Fix user-visible ones; leave internal identifiers
- [x] Report remaining intentional uses

The app product is CueGlass.app (executable CueGlass). Still intentional: Swift module and target CueFlow, project CueFlow.xcodeproj, scheme CueFlow, folders CueFlow/ and CueFlowTests/, bundle id com.example.cueflow, UTI com.example.cueflow.script, extension .cueflow, CUEFLOW_* environment variables, and the CueFlowICloudContainerIdentifier Info.plist key. Historical notes in CHANGELOG and the Codex handoff docs keep the working name. Verification of the built product is still ahead, so this bean stays in progress.
