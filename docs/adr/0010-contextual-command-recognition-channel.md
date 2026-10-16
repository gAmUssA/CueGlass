# Title

Use a contextual command channel for Follow Voice controls

# Status

accepted

# Date

2026-10-15

# Context

Human testing showed that script speech followed correctly while the English-prefixed transport commands were not recognized. Alternative interpretations from the script transcriber did not resolve the failure. Commands need stronger recognition for CueGlass's product name, but must remain isolated from script alignment and must not retain speech content.

# Decision

Keep `SpeechTranscriber` as the source of the best script-alignment hypothesis. Add an English `DictationTranscriber` to the same `SpeechAnalyzer` with contextual strings for the product name and command vocabulary. Route its results through a command-only event path. Maintain up to three separate, bounded four-word rolling hypotheses so the wake phrase and action can arrive in different incremental results without combining words from different interpretations. Track each module's finalization watermark independently so one transcriber's progress cannot confirm a volatile command from the other. Only exact prefixed phrases can invoke the existing transport actions. Model readiness and user-consented installation cover both modules; microphone capture remains user-initiated and audio/transcript content remains transient.

# Consequences

The command recognizer can use contextual vocabulary without allowing its wording to move the script. This adds the DictationTranscriber assets to English readiness and installation, a second result stream and module-specific confirmation state. Its hypothesis memory remains bounded to three interpretations of four words each. Human macOS 26+ command recognition and false-positive resistance still require operator verification.
