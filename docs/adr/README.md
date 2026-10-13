# Architecture Decision Records

One file per decision, named `NNNN-<kebab-title>.md`. Each record carries Title, Status, Date, Context, Decision and Consequences. Status is `proposed`, `accepted`, `deprecated` or `superseded by NNNN`. An accepted record is never rewritten into a different decision; a changed decision gets a new record that supersedes it.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-native-document-and-immutable-take.md) | Native document ownership with an immutable take and a pure timeline | accepted |
| [0002](0002-playback-snapshot-and-rendering.md) | Deterministic playback timeline, immutable take snapshot, TextKit 2 display-linked rendering | accepted |
| [0003](0003-icloud-document-storage.md) | iCloud Drive storage of self-contained `.cueflow` documents | accepted |

Sources: `CueFlow-Codex-Handoff.md` (product specification) and the architect decision note for task `cueglass-v1` (kept outside the repository). Work tracking lives in [Beans](../../.beans/) ([MVP milestone cueglass-aeqt](../../.beans/cueglass-aeqt--cueflow-v1-mvp.md)). All three records are delivered. Accepted ADR decisions do not constitute independent acceptance of the application; MVP acceptance remains open. ADR 0001 delivery is tracked by `cueglass-xfha`.
