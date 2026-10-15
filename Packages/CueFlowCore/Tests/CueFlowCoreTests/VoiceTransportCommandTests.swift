import CueFlowCore
import Testing

@Suite struct VoiceTransportCommandTests {
  @Test(arguments: [
    ("CueGlass, pause.", VoiceTransportCommand.pause),
    ("CUEGLASS resume!", VoiceTransportCommand.resume),
    ("CueGlass stop following.", VoiceTransportCommand.stopFollowing),
    ("CueGlass, stop take!", VoiceTransportCommand.stopTake),
  ])
  func recognizesPrefixedCommands(
    phrase: String, expected: VoiceTransportCommand
  ) {
    var matcher = VoiceTransportCommandMatcher()
    let words = recognizedWords(phrase)

    #expect(matcher.consume(event(words)) == expected)
  }

  @Test func requiresCueGlassPrefixAndFinalizedSpeech() {
    var matcher = VoiceTransportCommandMatcher()
    let words = recognizedWords("CueGlass pause")

    #expect(matcher.consume(event(words, isFinal: false, finalizedThrough: 0.2)) == nil)
    #expect(matcher.consume(event(recognizedWords("pause"))) == nil)
    #expect(matcher.consume(event(recognizedWords("Stop following"))) == nil)
  }

  @Test func volatileCommandFiresWhenFinalizationAdvancesWithoutReissuingText() {
    var matcher = VoiceTransportCommandMatcher()
    let words = recognizedWords("CueGlass pause")

    #expect(matcher.consume(event(words, isFinal: false, finalizedThrough: 0.2)) == nil)
    #expect(
      matcher.consume(
        TranscriptEvent(
          isFinal: false, rangeStart: 0.5, rangeEnd: 0.5, availableAt: 0.8, words: [],
          finalizedThrough: 0.5)) == .pause)
  }

  @Test func stablePrefixedCommandFiresWhenFinalizationDoesNotAdvance() {
    var matcher = VoiceTransportCommandMatcher()
    let words = recognizedWords("CueGlass pause")

    #expect(matcher.consume(event(words, isFinal: false), at: 10) == nil)
    #expect(matcher.hasPendingCandidate)
    #expect(matcher.advance(to: 10.74) == nil)
    #expect(matcher.advance(to: 10.76) == .pause)
    #expect(!matcher.hasPendingCandidate)
    #expect(matcher.lastResolvedAudioTime == words.last?.end)
  }

  @Test func revisedStableCommandRestartsItsConfirmationWindow() {
    var matcher = VoiceTransportCommandMatcher()
    let first = recognizedWords("CueGlass stop take")
    let revised = recognizedWords("CueGlass stop following")

    #expect(matcher.consume(event(first, isFinal: false), at: 10) == nil)
    #expect(matcher.consume(event(revised, isFinal: false), at: 10.5) == nil)
    #expect(matcher.advance(to: 11.24) == nil)
    #expect(matcher.advance(to: 11.26) == .stopFollowing)
  }

  @Test func shortStopMeansStopFollowingAndWaitsForStopTakeContinuation() {
    var matcher = VoiceTransportCommandMatcher()
    let stop = recognizedWords("CueGlass stop")

    #expect(matcher.consume(event(stop), at: 10) == nil)
    #expect(matcher.advance(to: 10.74) == nil)
    #expect(matcher.advance(to: 10.76) == .stopFollowing)

    var takeMatcher = VoiceTransportCommandMatcher()
    let first = recognizedWords("CueGlass stop")
    let complete = recognizedWords("CueGlass stop take")
    #expect(takeMatcher.consume(event(first, isFinal: true), at: 20) == nil)
    #expect(takeMatcher.consume(event(complete, isFinal: true), at: 20.1) == .stopTake)
  }

  @Test func findsCommandBeforeTrailingWordsInTheSameSpeechResult() {
    var matcher = VoiceTransportCommandMatcher()

    #expect(matcher.consume(event(recognizedWords("CueGlass pause and continue"))) == .pause)
  }

  @Test func volatileRevisionReplacesCommandBeforeFinalization() {
    var matcher = VoiceTransportCommandMatcher()
    let first = recognizedWords("CueGlass stop take")
    let revised = recognizedWords("CueGlass stop following")

    #expect(matcher.consume(event(first, isFinal: false, finalizedThrough: 0)) == nil)
    #expect(
      matcher.consume(
        event(revised, isFinal: false, finalizedThrough: 0)) == nil)
    #expect(
      matcher.consume(
        TranscriptEvent(
          isFinal: false, rangeStart: 1, rangeEnd: 1, availableAt: 1.2, words: [],
          finalizedThrough: 1)) == .stopFollowing)
  }

  @Test func requiresConfidentCloselySpokenWords() {
    var matcher = VoiceTransportCommandMatcher()

    #expect(
      matcher.consume(
        event([
          RecognizedWord(text: "CueGlass", start: 0, end: 0.2, confidence: 0.54),
          RecognizedWord(text: "pause", start: 0.25, end: 0.45),
        ])) == nil)
    #expect(
      matcher.consume(
        event([
          RecognizedWord(text: "CueGlass", start: 1, end: 1.2),
          RecognizedWord(text: "pause", start: 2.5, end: 2.7),
        ])) == nil)
  }

  @Test func acceptsACommandAcrossFinalResultBoundariesAndDeduplicatesIt() {
    var matcher = VoiceTransportCommandMatcher()
    let prefix = event(recognizedWords("CueGlass", startingAt: 3))
    let completion = event(recognizedWords("stop following", startingAt: 3.35))

    #expect(matcher.consume(prefix) == nil)
    #expect(matcher.consume(completion) == .stopFollowing)
    #expect(matcher.consume(completion) == nil)
  }

  @Test func recognizesCommandFromAlternativeWhenBestTranscriptMishearsWakePhrase() {
    var matcher = VoiceTransportCommandMatcher()
    let event = TranscriptEvent(
      isFinal: true, rangeStart: 0, rangeEnd: 0.7, availableAt: 0.7,
      words: recognizedWords("Google Glass pause"),
      commandAlternatives: [recognizedWords("Cue Glass pause")])

    #expect(matcher.consume(event) == .pause)
  }

  @Test func commandOnlyChannelCarriesWakePhraseAcrossIncrementalResults() {
    var matcher = VoiceTransportCommandMatcher()
    let wakePhrase = TranscriptEvent(
      isFinal: false, rangeStart: 0, rangeEnd: 0.2, availableAt: 0.2, words: [],
      commandAlternatives: [recognizedWords("CueGlass", startingAt: 0)], isCommandOnly: true)
    let action = TranscriptEvent(
      isFinal: true, rangeStart: 0.25, rangeEnd: 0.45, availableAt: 0.45, words: [],
      commandAlternatives: [recognizedWords("pause", startingAt: 0.25)], isCommandOnly: true)

    #expect(matcher.consume(wakePhrase, at: 10) == nil)
    let noSpeech = TranscriptEvent(
      isFinal: false, rangeStart: 0.15, rangeEnd: 0.2, availableAt: 0.2, words: [],
      finalizedThrough: 0.2, isCommandOnly: true)
    #expect(matcher.consume(noSpeech, at: 10.1) == nil)
    #expect(matcher.consume(action, at: 10.2) == .pause)
    #expect(!matcher.hasPendingCandidate)
  }

  @Test func commandOnlyChannelKeepsSplitCueGlassPrefixTogether() {
    var matcher = VoiceTransportCommandMatcher()
    let cue = TranscriptEvent(
      isFinal: false, rangeStart: 0, rangeEnd: 0.1, availableAt: 0.1, words: [],
      commandAlternatives: [recognizedWords("Cue", startingAt: 0)], isCommandOnly: true)
    let glass = TranscriptEvent(
      isFinal: false, rangeStart: 0.1, rangeEnd: 0.2, availableAt: 0.2, words: [],
      commandAlternatives: [recognizedWords("Glass", startingAt: 0.1)], isCommandOnly: true)
    let action = TranscriptEvent(
      isFinal: true, rangeStart: 0.2, rangeEnd: 0.65, availableAt: 0.65, words: [],
      commandAlternatives: [recognizedWords("stop take", startingAt: 0.2)], isCommandOnly: true)

    #expect(matcher.consume(cue, at: 20) == nil)
    #expect(matcher.consume(glass, at: 20.1) == nil)
    #expect(matcher.consume(action, at: 20.2) == .stopTake)
  }

  @Test func commandOnlyChannelKeepsAlternativeWakePhraseAcrossUpdates() {
    var matcher = VoiceTransportCommandMatcher()
    let wakePhrase = TranscriptEvent(
      isFinal: false, rangeStart: 0, rangeEnd: 0.45, availableAt: 0.45, words: [],
      commandAlternatives: [
        recognizedWords("Google Glass", startingAt: 0),
        recognizedWords("Cue Glass", startingAt: 0),
      ], isCommandOnly: true)
    let action = TranscriptEvent(
      isFinal: true, rangeStart: 0.5, rangeEnd: 0.7, availableAt: 0.7, words: [],
      commandAlternatives: [
        recognizedWords("pause", startingAt: 0.5),
        recognizedWords("pause", startingAt: 0.5),
      ], isCommandOnly: true)

    #expect(matcher.consume(wakePhrase, at: 25) == nil)
    #expect(matcher.consume(action, at: 25.1) == .pause)
  }

  @Test func scriptFinalizationDoesNotConfirmACommandChannelCandidate() {
    var matcher = VoiceTransportCommandMatcher()
    let command = TranscriptEvent(
      isFinal: false, rangeStart: 0, rangeEnd: 0.45, availableAt: 0.45, words: [],
      commandAlternatives: [recognizedWords("CueGlass pause")], isCommandOnly: true)
    let scriptFinality = TranscriptEvent(
      isFinal: false, rangeStart: 0.4, rangeEnd: 0.5, availableAt: 0.5, words: [],
      finalizedThrough: 0.5)
    let commandFinality = TranscriptEvent(
      isFinal: false, rangeStart: 0.4, rangeEnd: 0.5, availableAt: 0.5, words: [],
      finalizedThrough: 0.5, isCommandOnly: true)

    #expect(matcher.consume(command, at: 30) == nil)
    #expect(matcher.consume(scriptFinality, at: 30.5) == nil)
    #expect(matcher.consume(commandFinality, at: 30.6) == .pause)
  }

  @Test func acceptsWordsSharingOneSpeechAttributeTimeRange() {
    var matcher = VoiceTransportCommandMatcher()
    let words = [
      RecognizedWord(text: "CueGlass", start: 4, end: 4.8, confidence: 0.9),
      RecognizedWord(text: "stop", start: 4, end: 4.8, confidence: 0.9),
      RecognizedWord(text: "take", start: 4, end: 4.8, confidence: 0.9),
    ]

    #expect(matcher.consume(event(words)) == .stopTake)
  }

  @Test func acceptsCueGlassWhenTheTranscriberSplitsTheName() {
    var matcher = VoiceTransportCommandMatcher()

    #expect(matcher.consume(event(recognizedWords("Cue Glass stop take"))) == .stopTake)
  }

  @Test func canDisableEnglishCommandsForOtherLocales() {
    var matcher = VoiceTransportCommandMatcher(enabled: false)

    #expect(matcher.consume(event(recognizedWords("CueGlass stop take"))) == nil)
  }

  @Test func acceptsUnknownConfidenceOnlyAfterFinalization() {
    var matcher = VoiceTransportCommandMatcher()
    let words = [
      RecognizedWord(text: "CueGlass", start: 0, end: 0.2, confidence: -1),
      RecognizedWord(text: "pause", start: 0.25, end: 0.45, confidence: -1),
    ]

    #expect(matcher.consume(event(words)) == .pause)
  }

  private func event(
    _ words: [RecognizedWord], isFinal: Bool = true, finalizedThrough: Double? = nil
  ) -> TranscriptEvent {
    TranscriptEvent(
      isFinal: isFinal,
      rangeStart: words.first?.start ?? 0,
      rangeEnd: words.last?.end ?? 0,
      availableAt: words.last?.end ?? 0,
      words: words,
      finalizedThrough: finalizedThrough)
  }

  private func recognizedWords(_ phrase: String, startingAt start: Double = 0)
    -> [RecognizedWord]
  {
    phrase.split(whereSeparator: \.isWhitespace).enumerated().map { index, word in
      let wordStart = start + Double(index) * 0.25
      return RecognizedWord(
        text: String(word), start: wordStart, end: wordStart + 0.2, confidence: 0.9)
    }
  }
}
