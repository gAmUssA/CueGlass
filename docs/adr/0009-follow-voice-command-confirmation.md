# Title

Confirm stable Follow Voice commands and support the short stop phrase

# Status

accepted

# Date

2026-10-15

# Context

Spoken controls depend on live SpeechTranscriber updates. A recognized phrase can remain unchanged without a later result carrying a finalization watermark, so waiting only for that watermark can leave commands buffered indefinitely. The operator also asked to say “CueGlass, stop” and “CueGlass, stop take”.

# Decision

Keep the exact English-prefixed command set from ADR 0008 and add “CueGlass, stop” as Stop Following. Confirm a candidate at SpeechTranscriber's audio-time finalization watermark or after its exact wording remains unchanged for 0.75 seconds. Revisions restart the interval. Hold the short “CueGlass, stop” alias for the full interval even if already finalized, allowing “stop take” to supersede it. Poll the monotonic clock during quiet periods so confirmation does not depend on another transcript event. Withhold pending command candidates from script alignment. Retain the confidence threshold, phrase timing bounds, bounded memory, and manual-control priority from ADR 0008.

# Consequences

Commands work when a finalization-only update is omitted, and the short stop wording maps to the action the operator requested. The confirmation delay leaves a brief chance for revised wording or the longer Stop Take phrase to arrive before an action. Human command recognition and false-positive resistance remain macOS 26+ acceptance checks. This decision supersedes [ADR 0008](0008-spoken-follow-voice-transport.md).
