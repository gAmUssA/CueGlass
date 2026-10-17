---
# cueglass-1dwm
title: Prototype native voice-following scroll
status: completed
type: feature
priority: normal
created_at: 2026-10-14T03:26:59Z
updated_at: 2026-10-14T17:13:48Z
---

Owner explicitly authorized a separate Herdr-managed voice-following prototype after completed Axiom research cueglass-2gv1. Isolated experimental work; current MVP remains unchanged.

- [x] Implement deterministic script alignment and confidence-driven follow policy with manual override.
- [x] Exercise prerecorded audio through macOS 26 native speech APIs and record latency, position error, skips/repeats and silence behavior.
- [x] Provide reproducible tests, fixture provenance and a runnable prototype.
- [x] Review measured limitations and decide on live microphone integration separately.

Use docs/design/speech-following.md. No microphone capture, model download or deployment-target change without explicit scope; report absent installed assets or fixtures honestly.

## Prototype evidence (2026-10-14)

Standalone package `Experiments/VoiceFollow` (macOS 26 minimum confined to the package). Synthetic TTS fixtures only; no microphone, authorization request or model download. Real-time paced SpeechTranscriber with `fastResults` on this Mac: median 2 / p95 4–5 words behind, sentence-end follow p50 0.59–0.90 s, no false forward motion during silence or ad-lib, skip reacquired in 7 words, re-read jumped back in 7 words. Without `fastResults`, results batch every ~3.9 s (follow p50 2.19 s). Not human-speech evidence. See the experiment README for commands, measurements and limits.

This experiment stops at prerecorded audio. The macOS 26 live microphone integration is scoped separately in Bean cueglass-2mil.

## Integration decision (2026-10-14)

Keep the CueGlass app at macOS 14 and conditionally expose native SpeechAnalyzer/SpeechTranscriber following on macOS 26+. The app integration needs an explicit microphone permission flow, visible listening state, no audio retention, model readiness handling, source-offset-to-layout mapping, and a smooth shared PlaybackSession drive. The live microphone implementation is tracked separately as Bean cueglass-2mil.

## Summary of Changes

Completed the standalone prerecorded-audio prototype and its deterministic tests. Recorded the integration decision and follow-up scope; no microphone capture or app dependency was added to this experiment.
