# Title

Accept Prompter as a Follow Voice command wake phrase

# Status

accepted

# Date

2026-10-15

# Context

ADR 0009 limited the exact English command phrases to the CueGlass wake phrase. The operator approves “Prompter” as an additional wake phrase. The existing contextual recognizer and matcher already support it, but the operator help and documented contract did not expose that option.

# Decision

Accept either “CueGlass” (including the transcribed split form “Cue Glass”) or “Prompter” before the existing English command actions: Pause, Resume, Stop Following, and Stop Take. The short “stop” action means Stop Following and keeps the existing confirmation interval so “stop take” can complete. Preserve the confidence threshold, bounded command memory, contextual command-only channel, manual-control priority, and audio/transcript non-retention. This decision supersedes ADR 0009's CueGlass-only wake phrase while retaining its command timing and action semantics.

# Consequences

Operators may choose the product name or the familiar word “Prompter” while speaking commands. The accepted phrase set is explicit in the UI, design documentation, deterministic parser tests, and release notes. Both phrases remain English-only and exact; ordinary script words still cannot trigger a command without a wake phrase.
