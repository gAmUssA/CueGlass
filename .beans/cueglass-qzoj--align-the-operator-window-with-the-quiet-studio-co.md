---
# cueglass-qzoj
title: Align the operator window with the Quiet Studio concept
status: in-progress
type: task
created_at: 2026-10-17T04:35:49Z
updated_at: 2026-10-17T04:35:49Z
---

Owner asked to bring the UI as close as possible to docs/design/quiet-studio-concept.svg. Toolbar keeps the board's paragraph chevrons and a filled Presenting chip; the take bar uses lowercase labels and a signed remaining time; the locked-take notice moves over the editor; the stage caption and the pending-script notice use the board's wording as inline banners; the Controls panel reads pace inline; the state pill vocabulary gains Empty and End of script. The Text/Playback/Output inspector tabs the owner accepted in r9 stay in place of the board's disclosure sections.

## Work checklist

- [x] Toolbar: paragraph chevrons per board ②; Present chip shows "Presenting · <surface>" in the accent while live (the `NSMenuToolbarItem` discarded the custom pull-down, so the label never updated).
- [x] Take bar: lowercase "elapsed"/"remaining" labels, signed remaining time, pill vocabulary with Empty and End of script (board ⑤/⑩).
- [x] Editor: locked-take banner over the page with Stop Take (board ①/④); the stage footer keeps only the Follow Voice row while a take runs.
- [x] Stage: caption "Output preview · <display> W × H · exact output layout, scaled · shown unmirrored/mirrored"; inline notice banner with the board's newer-script wording and a Load button; accent speed slider; hint wording (board ⑥).
- [x] Controls panel: 600 × 116, pace reads inline at the end of the slider row, signed remaining (board ⑧).
- [x] Core and native suites green, strict format clean, branch CI green.
- [ ] Owner compares the r11 build against the board on the notched MacBook.

Decision: the Text / Playback / Output inspector tabs accepted in r9 stay; the board's disclosure sections predate that review. Toolbar key-hint caption under the transport (board ②) is not drawn — the unified toolbar has no room below the group; tooltips carry the keys.
