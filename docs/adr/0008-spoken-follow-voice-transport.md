# Title

Prefixed spoken transport controls for Follow Voice

# Status

superseded by 0009

# Date

2026-10-15

# Context

Follow Voice already processes transient speech while an operator presents. Spoken transport controls can help the operator keep attention on the camera, but common words in a script must not pause or stop a take accidentally. A spoken Pause also needs a way to hear Resume without requiring another microphone activation.

# Decision

Recognize only the English phrases “CueGlass, pause”, “CueGlass, resume”, “CueGlass, stop following”, and “CueGlass, stop take”. Accept the prefix as one token or as the adjacent words “Cue Glass” to account for speech transcription spelling. Match only finalized words with confidence of at least 0.55, require adjacent words within a short audio-time window, and retain only a bounded command prefix in memory. Volatile results and unprefixed script words never issue controls. The commands are available only during an explicitly started Follow Voice session with an English speech locale.

Spoken Pause pauses the shared PlaybackSession timeline and suspends transcript alignment while leaving the already authorized capture stream active only to hear a prefixed Resume or stop command. Resume resets the alignment hypothesis at its last confirmed script token before continuing the shared timeline. Any manual playback or navigation action retains priority and closes capture. Stop Following ends voice capture and leaves the take paused; Stop Take invokes the existing operator stop action and releases the take and presentation surface.

# Consequences

The command matcher keeps at most four normalized words and timestamps in transient memory; neither recognized command text nor audio is persisted. Manual control remains authoritative even while the spoken-command pause is active. English commands are intentionally limited to English locales; other locales continue to provide script following without spoken transport controls. Deterministic tests cover exact phrases, prefix spelling, confidence/finality, split-result assembly, duplicate results, pause/resume, stop routing, and manual override. Live human-speech command recognition remains a macOS 26+ manual acceptance check.
