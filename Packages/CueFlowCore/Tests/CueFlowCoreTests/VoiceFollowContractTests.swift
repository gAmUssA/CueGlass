import CueFlowCore
import Foundation
import Testing

@Test func voiceTokensRetainUTF16SourceRanges() {
  let text = "Hi 🐕 café, three!"
  let tokens = Tokenizer.tokens(in: text)

  #expect(tokens.map(\.text) == ["hi", "cafe", "3"])
  #expect(tokens.map(\.range) == [0..<2, 6..<10, 12..<17])
  #expect(
    (text as NSString).substring(
      with: NSRange(location: tokens[1].range.lowerBound, length: tokens[1].range.count)) == "café")
}

@Test func voiceLineTableMapsOffsetsMonotonicallyAndUsesNewLayout() {
  let first = VoiceLineTable(lines: [
    VoiceLine(utf16Range: 0..<5, minY: 0),
    VoiceLine(utf16Range: 5..<11, minY: 24),
    VoiceLine(utf16Range: 11..<16, minY: 48),
  ])
  let remeasured = VoiceLineTable(lines: [
    VoiceLine(utf16Range: 0..<5, minY: 0),
    VoiceLine(utf16Range: 5..<11, minY: 40),
    VoiceLine(utf16Range: 11..<16, minY: 80),
  ])

  #expect(first.y(forUTF16Offset: 5) == 24)
  #expect(first.y(forUTF16Offset: 10) == 24)
  #expect(first.y(forUTF16Offset: 11) == 48)
  #expect(first.y(forUTF16Offset: 15) == 48)
  #expect(first.y(forUTF16Offset: -1) == nil)
  #expect(remeasured.y(forUTF16Offset: 5) == 40)
  #expect(remeasured.lines.map(\.minY) == [0, 40, 80])
}

@Test func voiceEpochRejectsWorkFromBeforeManualSuspension() {
  var epoch = VoiceEpoch()
  let listeningEpoch = epoch.advance()
  #expect(epoch.accepts(listeningEpoch))

  let suspendedEpoch = epoch.advance()
  #expect(!epoch.accepts(listeningEpoch))
  #expect(epoch.accepts(suspendedEpoch))

  let resumedEpoch = epoch.advance()
  #expect(!epoch.accepts(suspendedEpoch))
  #expect(epoch.accepts(resumedEpoch))
}

@Test func voiceTimelineGlidesToARebasedCeilingAndNeverOvershoots() throws {
  var timeline = PlaybackTimeline()
  try timeline.setVelocity(50, at: 0)
  try timeline.play(at: 0)
  try timeline.setVoiceCeiling(100, at: 0)

  #expect(try timeline.position(at: 2) == 100)
  #expect(try timeline.position(at: 10) == 100)

  try timeline.setVoiceCeiling(150, at: 10)
  #expect(try timeline.position(at: 10) == 100)
  #expect(try timeline.position(at: 10.5) == 125)
  try timeline.setVoiceCeiling(20, at: 10.5)
  #expect(try timeline.position(at: 11) == 125)
}

@Test func aManualSeekClearsTheVoiceCeiling() throws {
  var timeline = PlaybackTimeline()
  try timeline.setVelocity(50, at: 0)
  try timeline.play(at: 0)
  try timeline.setVoiceCeiling(20, at: 0)
  try timeline.seek(to: 200, at: 2)

  #expect(timeline.voiceCeiling == nil)
  #expect(try timeline.position(at: 3) == 250)
}

@Test func transcriptAccumulatorBoundsAndClearsRecognizedWords() {
  var accumulator = TranscriptAccumulator()
  let words = (0..<120).map { index in
    RecognizedWord(text: "word\(index)", start: Double(index), end: Double(index + 1))
  }
  accumulator.apply(
    TranscriptEvent(
      isFinal: true, rangeStart: 0, rangeEnd: 120, availableAt: 120, words: words))

  #expect(accumulator.finalized.count == TranscriptAccumulator.retainedWordLimit)
  #expect(accumulator.finalized.first?.text == "word24")
  accumulator.clear()
  #expect(accumulator.hypothesis.isEmpty)
}

@Test func transcriptFinalizationWatermarkPromotesUnchangedVolatileWords() {
  var accumulator = TranscriptAccumulator()
  let words = [
    RecognizedWord(text: "north", start: 0, end: 0.3),
    RecognizedWord(text: "wind", start: 0.31, end: 0.6),
  ]
  accumulator.apply(
    TranscriptEvent(
      isFinal: false, rangeStart: 0, rangeEnd: 0.6, availableAt: 0.8, words: words))
  #expect(accumulator.finalized.isEmpty)
  #expect(accumulator.volatile == words)

  accumulator.apply(
    TranscriptEvent(
      isFinal: false, rangeStart: 0.6, rangeEnd: 0.6, availableAt: 1.0, words: [],
      finalizedThrough: 0.6))

  #expect(accumulator.finalized == words)
  #expect(accumulator.volatile.isEmpty)

  accumulator.apply(
    TranscriptEvent(
      isFinal: true, rangeStart: 0, rangeEnd: 0.6, availableAt: 1.1, words: words,
      finalizedThrough: 0.6))
  #expect(accumulator.finalized == words)
}

@Test func transcriptBatchesPreserveDistinctWordsSharingOneAudioRange() {
  var accumulator = TranscriptAccumulator()
  let words = ["steady", "hands", "forward"].map {
    RecognizedWord(text: $0, start: 0.2, end: 0.9)
  }

  accumulator.apply(
    TranscriptEvent(
      isFinal: false, rangeStart: 0.2, rangeEnd: 0.9, availableAt: 1.0, words: words,
      finalizedThrough: 0.9))
  #expect(accumulator.finalized == words)
  #expect(accumulator.volatile.isEmpty)

  accumulator.apply(
    TranscriptEvent(
      isFinal: true, rangeStart: 0.2, rangeEnd: 0.9, availableAt: 1.1, words: words,
      finalizedThrough: 0.9))
  #expect(accumulator.finalized == words)
}
