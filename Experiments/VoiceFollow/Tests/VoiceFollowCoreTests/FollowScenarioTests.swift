import Testing

@testable import VoiceFollowCore

private let script = ScriptIndex(text: DemoScript.text)

/// Token range of paragraph `p` (0-based).
private func paragraph(_ p: Int) -> Range<Int> {
  let indices = script.paragraphOfToken.indices.filter { script.paragraphOfToken[$0] == p }
  return indices.first!..<(indices.last! + 1)
}

private func run(
  _ steps: [ReadingStep], options: SyntheticOptions = SyntheticOptions(),
  commands: [TimedCommand] = []
) -> (Evaluation, ReplayResult, GroundTruth) {
  let take = Synthesizer.take(script: script, steps: steps, options: options)
  let result = Replay.run(
    script: script, events: take.events, commands: commands, duration: take.duration)
  let truth = GroundTruth(script: script, segments: take.truth)
  return (Evaluator.evaluate(result, truth: truth), result, truth)
}

private func displays(_ result: ReplayResult, from start: Double, to end: Double) -> [Double] {
  result.samples.filter { $0.time >= start && $0.time < end }.map(\.display)
}

@Suite struct ScriptIndexTests {
  @Test func tokenizesDemoScriptIntoParagraphsAndSentences() {
    #expect(script.count == 150)
    #expect(Set(script.paragraphOfToken) == [0, 1, 2, 3])
    #expect(script.sentences.count == 12)
    #expect(script.text(of: script.sentences[0]).hasPrefix("Every evening"))
    #expect(script.text(of: script.sentences[0]).hasSuffix("harbor light"))
  }

  @Test func normalizesCaseApostrophesAndNumberWords() {
    #expect(
      Tokenizer.tokens(in: "Don't  STOP—three, 3!").map(\.text) == ["dont", "stop", "3", "3"])
    #expect(WordMatch.score("harbour", "harbor") == 1)
    #expect(WordMatch.score("the", "she") == 0)
  }
}

@Suite struct EvaluationTests {
  @Test func wordErrorRateCountsSubstitutionsInsertionsAndDeletions() {
    let reference = ["the", "keeper", "climbed", "the", "stairs"]
    #expect(Evaluator.wordErrorRate(reference: reference, hypothesis: reference) == 0)
    #expect(
      Evaluator.wordErrorRate(
        reference: reference, hypothesis: ["the", "keeper", "climb", "stairs"]) == 0.4)
    #expect(
      Evaluator.wordErrorRate(reference: reference, hypothesis: reference + ["um", "yes"]) == 0.4)
  }

  @Test func groundTruthIsExactAtSegmentBoundariesAndHoldsThroughQuiet() {
    let segments = [
      TruthSegment(kind: .speech, start: 0, end: 2, scriptFirst: 0, scriptLast: 5),
      TruthSegment(kind: .silence, start: 2, end: 4),
      TruthSegment(kind: .speech, start: 4, end: 6, scriptFirst: 40, scriptLast: 45),
    ]
    let truth = GroundTruth(script: script, segments: segments)
    #expect(truth.spokenPosition(at: 0) == -1)
    #expect(truth.spokenPosition(at: 2) == 5)
    #expect(truth.spokenPosition(at: 3.9) == 5)
    #expect(truth.spokenPosition(at: 4.01) == 5)
    #expect(truth.spokenPosition(at: 6) == 45)
    #expect(truth.kind(at: 3) == .silence)
  }
}

@Suite struct FollowScenarioTests {
  @Test func verbatimReadTracksWithinOneWordAndNeverRunsAhead() {
    let (evaluation, _, _) = run([.read(0..<script.count)])
    #expect(evaluation.medianAbsError <= 1)
    #expect(evaluation.p95AbsError <= 2)
    #expect(evaluation.maxOvershoot <= 0)
    #expect(evaluation.jumps == 0)
    #expect(evaluation.backwardMotions == 0)
  }

  @Test func silenceHoldsPositionWithoutFalseMotion() {
    let first = script.sentences[1]
    let (evaluation, result, truth) = run([
      .read(0..<first.upperBound), .silence(5),
      .read(first.upperBound..<script.sentences[3].upperBound),
    ])
    let silence = truth.segments.first { $0.kind == .silence }!
    // After the pending final result settles, the display does not move for the rest of the pause.
    let held = displays(result, from: silence.start + 1.5, to: silence.end)
    #expect(Set(held).count == 1)
    #expect(held.first == Double(first.upperBound - 1))
    #expect(evaluation.maxQuietOvershoot <= 0)
    #expect(evaluation.quietFalseMotion == 0)
    #expect(result.decisions.contains { $0.decision == .hold(.silence) })
  }

  @Test func adlibWithCommonScriptWordsCausesNoForwardMotion() {
    let split = script.sentences[4].lowerBound + 4
    let (evaluation, result, truth) = run([
      .read(0..<split),
      .adlib("and then she said the light and the lens and the glass were all fine for the night"),
      .read(split..<script.sentences[6].upperBound),
    ])
    let adlib = truth.segments.first { $0.kind == .adlib }!
    #expect(
      displays(result, from: adlib.start + 1.5, to: adlib.end).allSatisfy {
        $0 <= Double(split - 1)
      })
    #expect(evaluation.maxQuietOvershoot <= 0)
    #expect(evaluation.quietFalseMotion == 0)
    #expect(evaluation.jumps == 0)
    #expect(evaluation.p95AbsError <= 4)
  }

  @Test func skippedParagraphReacquiresWithinSixWords() {
    let (evaluation, _, _) = run([.read(paragraph(0)), .read(paragraph(2))])
    #expect(evaluation.recoveries.count == 1)
    let recovery = evaluation.recoveries[0]
    #expect((recovery.words ?? .max) <= 6)
    #expect(evaluation.jumps == 1)
    #expect(evaluation.maxOvershoot <= 0)
  }

  @Test func weakTwoWordMatchElsewhereNeverJumps() {
    // "the rocks" and "sandy path" exist only in later paragraphs; two-word coincidences
    // inside an ad-lib must not move the display there.
    let (evaluation, result, _) = run([
      .read(paragraph(0)), .adlib("we never went near the rocks or the sandy path that summer"),
      .read(paragraph(1)),
    ])
    #expect(evaluation.jumps == 0)
    #expect(result.samples.allSatisfy { $0.display <= Double(paragraph(1).upperBound - 1) })
    #expect(evaluation.maxQuietOvershoot <= 0)
  }

  @Test func shortRepeatHoldsInsteadOfJumpingBack() {
    let s2 = script.sentences[2]
    let repeated = (s2.upperBound - 5)..<s2.upperBound
    let (evaluation, _, _) = run([
      .read(0..<s2.upperBound), .read(repeated), .read(paragraph(1)),
    ])
    #expect(evaluation.jumps == 0)
    #expect(evaluation.backwardMotions == 0)
    #expect(evaluation.maxAheadOfFurthest <= 0)
    #expect(evaluation.settledErrors.allSatisfy { abs($0) <= 1 })
  }

  @Test func shortRepeatFromFurtherBackHoldsInsteadOfJumping() {
    // Five words from the middle of sentence 2, re-said after sentence 3: outside the local
    // window but below the back-jump evidence bar. The echo starts with "she", which is also
    // the next script word, so a one-word advance is the documented bound.
    let s2 = script.sentences[2]
    let echo = (s2.lowerBound + 3)..<(s2.lowerBound + 8)
    let (evaluation, _, _) = run([
      .read(0..<script.sentences[3].upperBound), .read(echo), .read(script.sentences[4]),
    ])
    #expect(evaluation.jumps == 0)
    #expect(evaluation.backwardMotions == 0)
    #expect(evaluation.maxAheadOfFurthest <= 1)
  }

  @Test func fiveWordEchoOfEarlierParagraphStaysBelowBackJumpBar() {
    // "carried a small lantern a" (sentence 1) re-said after sentence 4: none of it fits the
    // local window, so only the back-jump evidence bar keeps the display from jumping back.
    let s1 = script.sentences[1]
    let echo = (s1.lowerBound + 1)..<(s1.lowerBound + 6)
    let (evaluation, _, _) = run([
      .read(0..<script.sentences[4].upperBound), .read(echo), .read(script.sentences[5]),
    ])
    #expect(evaluation.jumps == 0)
    #expect(evaluation.backwardMotions == 0)
    #expect(evaluation.maxAheadOfFurthest <= 0)
  }

  @Test func ambiguousPhraseNeverTriggersAJump() {
    // The six-word phrase appears in paragraphs 2 and 3. A reader skipping from paragraph 1
    // into paragraph 3 must not be placed on the nearer paragraph-2 copy.
    let custom = ScriptIndex(
      text: """
        Morning fog covered the dock while gulls waited.

        Ropes were coiled near the mast and the crew checked every knot twice before the tide \
        rose against them. Turn the brass key slowly now. Crates were stacked high.

        Inside the cabin it was warm. Turn the brass key slowly now. The engine woke at once.
        """)
    let starts = custom.tokens.indices.filter { custom.tokens[$0].text == "turn" }
    let phrase = Tokenizer.tokens(in: "Turn the brass key slowly now").count
    let take = Synthesizer.take(
      script: custom, steps: [.read(0..<8), .read(starts[1]..<custom.count)])
    let result = Replay.run(script: custom, events: take.events, duration: take.duration)
    let wrong = starts[0]..<(starts[0] + phrase)
    let targets = result.decisions.compactMap { record -> Int? in
      switch record.decision {
      case .advance(let index), .jump(_, let index): index
      case .none, .hold: nil
      }
    }
    #expect(starts.count == 2)
    #expect(starts[0] > 8 + 16)
    #expect(!targets.contains { wrong.contains($0) })
    #expect(result.samples.last?.display == Double(custom.count - 1))
  }

  @Test func longRereadOfEarlierPassageJumpsBackThenFollows() {
    let (evaluation, result, _) = run([
      .read(paragraph(0)), .read(paragraph(1)), .read(paragraph(1)),
    ])
    #expect(evaluation.jumps == 1)
    #expect(evaluation.recoveries.count == 1)
    #expect((evaluation.recoveries[0].words ?? .max) <= 7)
    #expect(result.samples.last?.display == Double(paragraph(1).upperBound - 1))
  }

  @Test func repeatedScriptPhraseDoesNotPullToWrongOccurrence() {
    // "the harbor light" ends sentence 0 and also appears in paragraph 2. Reading sentence 0
    // must never place the display in paragraph 2.
    let (_, result, _) = run([.read(script.sentences[0]), .silence(2), .read(script.sentences[1])])
    #expect(result.samples.allSatisfy { $0.display < Double(paragraph(1).lowerBound) })
    #expect(result.samples.last?.display == Double(script.sentences[1].upperBound - 1))
  }

  @Test func revisedPartialsNeverMoveDisplayBackward() {
    var options = SyntheticOptions()
    options.revisedTokens = Set(stride(from: 3, to: 60, by: 4))
    let (evaluation, _, _) = run([.read(0..<60)], options: options)
    #expect(evaluation.revisions == options.revisedTokens.count)
    #expect(evaluation.backwardMotions == 0)
    #expect(evaluation.maxOvershoot <= 0)
    #expect(evaluation.p95AbsError <= 3)
  }

  @Test func lowConfidenceSentenceDoesNotMoveDisplay() {
    let s1 = script.sentences[1]
    var options = SyntheticOptions()
    options.lowConfidenceTokens = Set(s1)
    let (_, result, truth) = run(
      [.read(0..<s1.lowerBound), .read(s1), .silence(1), .read(script.sentences[2])],
      options: options)
    let lastGood = Double(s1.lowerBound - 1)
    #expect(
      displays(result, from: truth.segments[1].start, to: truth.segments[2].end).allSatisfy {
        $0 <= lastGood
      })
    #expect(result.decisions.contains { $0.decision == .hold(.lowConfidence) })
  }
}

@Suite struct ManualPriorityTests {
  @Test func pauseSuspendsFollowingUntilExplicitResume() {
    let take = Synthesizer.take(script: script, steps: [.read(0..<script.sentences[5].upperBound)])
    let result = Replay.run(
      script: script, events: take.events,
      commands: [
        TimedCommand(time: 4, command: .pause), TimedCommand(time: 12, command: .resumeFollowing),
      ],
      duration: take.duration)
    let paused = displays(result, from: 4, to: 12)
    #expect(Set(paused).count == 1)
    #expect(result.samples.last?.display == Double(script.sentences[5].upperBound - 1))
  }

  @Test func scrubAndStepWinOverSpeechAndResumeReacquiresFromThere() {
    let p2 = paragraph(2)
    let take = Synthesizer.take(
      script: script, steps: [.read(paragraph(0)), .silence(1), .read(p2)])
    let resumeAt = take.truth[2].start - 0.2
    let result = Replay.run(
      script: script, events: take.events,
      commands: [
        TimedCommand(time: 2, command: .scrub(to: p2.lowerBound + 10)),
        TimedCommand(time: 3, command: .step(-10)),
        TimedCommand(time: resumeAt, command: .resumeFollowing),
      ], duration: take.duration)
    #expect(displays(result, from: 3, to: resumeAt).allSatisfy { $0 == Double(p2.lowerBound) })
    let truth = GroundTruth(script: script, segments: take.truth)
    let evaluation = Evaluator.evaluate(result, truth: truth)
    #expect(evaluation.jumps == 0)
    #expect(result.samples.last?.display == Double(p2.upperBound - 1))
  }

  @Test func timedModeIgnoresSpeechEntirely() {
    let take = Synthesizer.take(script: script, steps: [.read(paragraph(0))])
    let result = Replay.run(
      script: script, events: take.events,
      commands: [TimedCommand(time: 0, command: .setMode(.timed))],
      duration: take.duration)
    #expect(result.samples.allSatisfy { $0.display == -1 && $0.mode == .timed })
    #expect(result.decisions.isEmpty)
  }
}
