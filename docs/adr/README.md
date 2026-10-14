# Architecture Decision Records

One file per decision, named `NNNN-<kebab-title>.md`. Each record carries Title, Status, Date, Context, Decision and Consequences. Status is `proposed`, `accepted`, `deprecated` or `superseded by NNNN`. An accepted record is never rewritten into a different decision; a changed decision gets a new record that supersedes it.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-native-document-and-immutable-take.md) | Native document ownership with an immutable take and a pure timeline | accepted |
| [0002](0002-playback-snapshot-and-rendering.md) | Deterministic playback timeline, immutable take snapshot, TextKit 2 display-linked rendering | accepted — speed clauses superseded by 0004 |
| [0003](0003-icloud-document-storage.md) | iCloud Drive storage of self-contained `.cueflow` documents | accepted |

| [0004](0004-lines-per-minute-direction-and-schema.md) | LPM, direction, bounded navigation and schema | accepted |
| [0005](0005-native-surfaces-commands-and-timing.md) | Native surfaces, commands, timing and reading aids | accepted |
| [0006](0006-public-github-actions-release-build.md) | Public GitHub Actions build and unnotarized prerelease assets | accepted |
| [0007](0007-shared-timeline-voice-glide-ceiling.md) | Shared timeline voice-follow glide ceiling | accepted |

Sources: `CueFlow-Codex-Handoff.md` (product specification), the architect decision note for task `cueglass-v1` (kept outside the repository), and Follow Voice task requirements. Work tracking lives in [Beans](../../.beans/) ([MVP milestone cueglass-aeqt](../../.beans/cueglass-aeqt--cueflow-v1-mvp.md)). All seven records are delivered. Accepted ADR decisions do not constitute independent acceptance of the application; MVP acceptance remains open. ADR 0001 delivery is tracked by `cueglass-xfha`.
