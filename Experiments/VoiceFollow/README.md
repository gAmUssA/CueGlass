# VoiceFollow experiment

This is a standalone prototype for following a presenter's voice through a known script. It is not part of the CueGlass app. Nothing in `CueFlow/`, `Packages/` or the Xcode project depends on it. Its macOS 26 minimum applies only to this package. Background is in [`docs/design/speech-following.md`](../../docs/design/speech-following.md).

**Scope:**
- Prerecorded files only. No microphone capture, no Speech authorization request and no model download.
- The Speech path refuses to run when assets are missing.
- Fixtures are synthetic text-to-speech audio. The results say nothing about human speech, accents, room noise or real microphones.

## Layout

| Target | Role |
|---|---|
| `VoiceFollowCore` | Pure logic with no Speech dependency: the script token index, the volatile/final transcript merge, Smith–Waterman windowed alignment, the confidence follow policy, a simulated logical scroll with manual priority, deterministic replay on an injected clock, metrics, and a synthetic transcript generator. |
| `VoiceFollowSpeech` | `SpeechAnalyzer` + `SpeechTranscriber` file transcription, with offline and real-time paced input. It also holds a read-only capability probe and fixture synthesis through `/usr/bin/say`. |
| `voicefollow` | The command-line harness. |

## Follow policy

The follower tracks a position: the index of the last script token confirmed as spoken. Position is a source-token index, never a layout coordinate.

- **Advancing.** Each transcript update aligns the last 8 recognized words against a window from 3 tokens behind to 16 tokens ahead.
  - The display advances only when two adjacent matched words lie beyond the confirmed position. This stops a single coincidental word (for example "the" in an ad-lib) from moving the display.
  - The display never moves backward through a local match.
- **Confidence.** Unmatched recent words degrade confidence: `locked`, then `tentative` (3 misses), then `lost` (8 misses).
  - While tentative, the follower needs 3 matches.
  - While lost, any motion needs reacquisition evidence (below).
- **Jumps and reacquisition** use the whole script and require all of the following:
  - 4 matched words, or 6 to jump backward;
  - at most 1 trailing unmatched word;
  - a 4-point score margin over any other location for the same latest word.

  Ambiguous repeated phrases therefore never move the display.
- **Recognized words.** Words with a reported confidence below 0.3 never match. Volatile results observed on macOS 27.0.1 report no confidence; they match on alignment evidence alone.
- **Silence.** The follower never extrapolates pace. Silence holds the display, and a `hold(silence)` is reported after 1.2 s without words.
- **Manual control.** Pause, scrub, step and a switch to Timed mode suspend following. Only an explicit `resumeFollowing` re-arms it. It restarts from the operator's position with tentative confidence and uses only speech heard after the resume. Timed mode ignores speech entirely.
- **Display motion.** The simulated display glides forward at most 10 words/s and moves backward only by a confirmed jump. It stands in for the app timeline; nothing runs per display frame.

## Commands

Run each command from this directory. It needs Xcode 26 or newer (developed with Xcode 27.0, Swift 6.4, on macOS 27.0.1, Apple M5 Max).

```bash
swift test                                    # 20 deterministic tests, no audio
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift build
.build/debug/voicefollow probe                # read-only capability report
.build/debug/voicefollow synthetic            # metrics for synthetic transcript scenarios
.build/debug/voicefollow make-fixtures --out .fixtures
.build/debug/voicefollow transcribe --audio .fixtures/verbatim.wav --pacing realtime --fast \
  --out .runs/verbatim-realtime-fast.json
.build/debug/voicefollow evaluate --trace .runs/verbatim-realtime-fast.json \
  --manifest .fixtures/verbatim.json
```

`.fixtures/` and `.runs/` are gitignored, and no audio is committed.

Each fixture JSON records its provenance (voice, rate, synthesizer and trimming) and labelled segments:
- Each sentence is spoken separately with `say -v <voice> -r <rate> --data-format=LEI16@16000`.
- Edges are trimmed and 0.35 s gaps are inserted, so segment boundaries are exact.
- Inside a segment, position is interpolated by word length.

Regenerating a fixture on the same host produced a byte-identical WAV.

**Fixture variants** (Samantha at 175 wpm unless noted):

| Variant | Content |
|---|---|
| `verbatim` | The whole script |
| `silence` | A 5 s pause mid-script |
| `repeat` | A 5-word tail repeat and a 2-sentence re-read |
| `skip` | Paragraph 3 skipped |
| `adlib` | A 19-word ad-lib |
| `fast` | Samantha at 230 wpm |
| `daniel` | Daniel (en_GB) at 185 wpm |

**Pacing modes:**
- `--pacing realtime` delivers 0.1 s buffers no faster than wall-clock audio time. Result arrival minus audio time then approximates live latency, minus capture and device latency, which are not modelled.
- `--pacing offline` hands over the whole file. It measures throughput only. Its replay uses finals only, at their audio end, because offline volatile results report a range to the end of the file.

## Measured results

These figures are for synthetic TTS audio on one Mac (macOS 27.0.1, M5 Max) and are not evidence about human speech. Word counts are script tokens.

**Pace:** real-time paced runs with `fastResults` took 34.9–47.0 s of audio at about 1.0× wall time. Offline runs took 0.36–0.49 s of wall time for the same files.

**Position error** (median / p95, in words) is measured while speech is playing. A negative signed error means the display is behind.

| Run | WER | Median / p95 | Signed mean | Follow at sentence end, p50 / p95 |
|---|---|---|---|---|
| verbatim, realtime + fast (2 runs) | 1.3% | 2 / 4 | −2.4 | 0.59 / 0.85 s |
| verbatim, realtime, no fast | 1.3% | 8 / 12.5 | −8.3 | 2.19 / 2.55 s |
| fast 230 wpm, realtime + fast | 2.0% | 3 / 5 | −3.2 | 0.90 / 1.22 s |
| daniel en_GB, realtime + fast | 1.3% | 2 / 4 | −2.3 | 0.77 / 0.85 s |
| silence, realtime + fast | 0% | 2 / 4 | −2.4 | 0.75 / 0.97 s |
| adlib, realtime + fast | 0.9% | 2 / 5 | −2.5 | 0.73 / 0.99 s |
| skip, realtime + fast | 1.8% | 2 / 5 | −4.1 | 0.65 / 0.90 s |
| repeat, realtime + fast | 1.5% | 2.5 / 33 | −1.0 | 0.73 / 0.85 s |

**What the real-time runs showed:**
- **No false forward motion in any real-time run.** The display was never ahead of the furthest word spoken. There was no motion past the true position during silence or the ad-lib, and no backward motion except the one confirmed re-read jump.
- **Skip.** The display reacquired after 7 words (1.67 s), with one jump.
- **Re-read.** It jumped back after 7 words (2.07 s) and forward again after 6 words (1.79 s). The p95 of 33 reflects the deliberate hold before the backward jump is confirmed.
- **Ad-lib.** Confidence went `lost` for 4.8 s and recovered with no jump.

**Latency without `fastResults`:**
- Real-time results arrived in batches about every 3.9 s, and finals arrived about 3.9 s after the audio they covered.
- With `fastResults`, volatile updates arrived about once per second, and finals about 1.0 s after their range end (p95 1.1 s).
- Per finalized word, the first result that showed the word arrived 0.68 s after the word ended (p50; p95 1.0–3.6 s, depending on the fixture). Finalization took 2.3–2.9 s at p50.

**Recognizer output:**
- Volatile results grow word by word, often mid-word ("keep" → "keeper").
- The trace counts every changed word text as a revision: 424–633 per take with `fastResults`. None moved the display backward.

**Process cost** (the harness process only; recognition may run in a system service that is not measured): 0.30–0.41 s of CPU and 22–23 MiB maximum RSS per real-time take. Model preparation took 0.02–0.06 s with assets already installed.

**Synthetic transcript scenarios** use 0.3 s volatile latency. Verbatim, silence and ad-lib tracked at a median of 1 / p95 of 2 words with no false motion. A skip recovered within 6 words, and a long re-read within 7.

## Known limits

- **Coincidental next word.** A re-said phrase or ad-lib that starts with the exact next script word can advance the display by one word. The test bounds this. A stricter "two new words" rule left the last word of every sentence unconfirmed, so it was rejected.
- **Glide through a skip.** Within the 16-word local window, a skip glides instead of seeking, so the display passes over skipped text for about 1–2 s.
- **Approximate volatile word times.** Volatile runs carry no per-word time or confidence, so word times there are spread evenly across the run.
- **Numbers.** Numerals fold only for zero–twenty, and mixed forms such as "twenty one" against "21" do not match.
- **Asset status mismatch.** `AssetInventory.status` reports `supported`, while `SpeechTranscriber.installedLocales` lists `en_US`. The transcriber runs only when the locale is listed as installed.
- **Not measured:**
  - human speakers or accents
  - microphone or device capture latency
  - room noise
  - long takes (over 47 s)
  - offline behaviour after asset eviction
  - networking disabled during analysis
  - Macs other than this one
  - frame-path cost inside the app

## Before a live microphone spike

The next step needs explicit owner authorization and these items settled first:
- A microphone entitlement and usage strings, with authorization verified for the chosen API. Here `SFSpeechRecognizer.authorizationStatus` was `notDetermined` and file transcription still ran.
- A visible listening state.
- An audio-retention policy.
- Speech running behind `#available(macOS 26, *)`, with no change to the app's deployment target.
