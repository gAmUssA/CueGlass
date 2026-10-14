import CueFlowCore
import Foundation

/// One step of a scripted reading used to synthesize transcript streams.
public enum ReadingStep: Sendable, Equatable {
  case read(Range<Int>)
  case adlib(String)
  case silence(Double)
}

public struct SyntheticOptions: Sendable {
  /// Audio seconds per unit of `TruthSegment.weight`.
  public var secondsPerWeight = 0.045
  /// Delay from a word's end until a volatile result containing it is available.
  public var volatileLatency = 0.3
  /// Delay from a step's end until its final result is available.
  public var finalLatency = 1.0
  /// Script token indices whose first volatile appearance is a wrong word, later revised.
  public var revisedTokens: Set<Int> = []
  /// Script token indices recognized with low confidence.
  public var lowConfidenceTokens: Set<Int> = []
  public var confidence = 0.9
  public var lowConfidence = 0.1

  public init() {}
}

public struct SyntheticTake: Sendable {
  public var events: [TranscriptEvent]
  public var truth: [TruthSegment]
  public var duration: Double
}

/// Deterministic transcript streams with known ground truth; no audio or randomness.
public enum Synthesizer {
  public static func take(
    script: ScriptIndex, steps: [ReadingStep], options: SyntheticOptions = SyntheticOptions()
  )
    -> SyntheticTake
  {
    var time = 0.0
    var events: [TranscriptEvent] = []
    var truth: [TruthSegment] = []
    for step in steps {
      switch step {
      case .silence(let seconds):
        truth.append(TruthSegment(kind: .silence, start: time, end: time + seconds))
        time += seconds
      case .read(let range):
        let words = range.map { index -> (String, Int?) in (script.tokens[index].text, index) }
        let segmentEnd = emit(words, from: time, options: options, into: &events)
        truth.append(
          TruthSegment(
            kind: .speech, start: time, end: segmentEnd, scriptFirst: range.lowerBound,
            scriptLast: range.upperBound - 1, text: script.text(of: range)))
        time = segmentEnd
      case .adlib(let text):
        let words = Tokenizer.tokens(in: text).map { ($0.text, Int?.none) }
        let segmentEnd = emit(words, from: time, options: options, into: &events)
        truth.append(TruthSegment(kind: .adlib, start: time, end: segmentEnd, text: text))
        time = segmentEnd
      }
    }
    return SyntheticTake(events: events, truth: truth, duration: time + options.finalLatency + 1)
  }

  private static func emit(
    _ words: [(String, Int?)], from start: Double, options: SyntheticOptions,
    into events: inout [TranscriptEvent]
  ) -> Double {
    var time = start
    var recognized: [RecognizedWord] = []
    var shownWrong: Set<Int> = []
    for (text, index) in words {
      let end = time + TruthSegment.weight(of: text) * options.secondsPerWeight
      let low = index.map { options.lowConfidenceTokens.contains($0) } ?? false
      recognized.append(
        RecognizedWord(
          text: text, start: time, end: end,
          confidence: low ? options.lowConfidence : options.confidence))
      var volatileWords = recognized
      if let index, options.revisedTokens.contains(index), !shownWrong.contains(index) {
        shownWrong.insert(index)
        volatileWords[volatileWords.count - 1].text = "zzrevised"
      }
      events.append(
        TranscriptEvent(
          isFinal: false, rangeStart: start, rangeEnd: end,
          availableAt: end + options.volatileLatency,
          words: volatileWords))
      time = end
    }
    events.append(
      TranscriptEvent(
        isFinal: true, rangeStart: start, rangeEnd: time, availableAt: time + options.finalLatency,
        words: recognized))
    return time
  }
}
