---
# cueglass-wz3h
title: Document CueGlass voice-follow integration path
status: completed
type: task
priority: normal
created_at: 2026-10-14T17:12:00Z
updated_at: 2026-10-14T17:13:11Z
---

Research and document the integration path from the standalone VoiceFollow experiment into CueGlass. Decide whether to retain the macOS 14 baseline or raise it, capture Apple API availability, permissions and model requirements, map token positions into CueGlass playback/layout, and define validation boundaries. Keep microphone capture out of this research change; track app integration separately.

- [x] Inspect standalone experiment and confirm its current test and measurement evidence.
- [x] Verify API availability, microphone permission, entitlement, and model-install requirements against Apple documentation.
- [x] Record the integration recommendation and CueGlass playback/layout connection.
- [x] Define the separate implementation goal and validation boundaries.

## Summary of Changes

Documented a macOS 14-compatible integration plan using SpeechAnalyzer and SpeechTranscriber behind macOS 26 availability checks. Captured microphone permission/entitlement and model-install requirements, mapped prototype token indexes to TextKit 2 and the shared PlaybackSession, and defined manual validation boundaries. Created follow-up Bean cueglass-2mil for app integration.
