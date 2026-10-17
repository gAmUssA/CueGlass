import Foundation

/// Labelled interval of a take. Speech segments name the inclusive script tokens read.
public struct TruthSegment: Sendable, Codable, Equatable {
  public enum Kind: String, Sendable, Codable {
    case speech, adlib, silence
  }

  public var kind: Kind
  public var start: Double
  public var end: Double
  public var scriptFirst: Int?
  public var scriptLast: Int?
  public var text: String

  public init(
    kind: Kind, start: Double, end: Double, scriptFirst: Int? = nil, scriptLast: Int? = nil,
    text: String = ""
  ) {
    self.kind = kind
    self.start = start
    self.end = end
    self.scriptFirst = scriptFirst
    self.scriptLast = scriptLast
    self.text = text
  }

  /// Relative spoken duration of a word; used for interpolation inside a speech segment.
  public static func weight(of word: String) -> Double { Double(word.count + 2) }
}

/// Ground-truth spoken position. Inside a speech segment the last spoken word is
/// interpolated by word weight, so it is exact at segment boundaries and approximate inside.
public struct GroundTruth: Sendable {
  public let script: ScriptIndex
  public let segments: [TruthSegment]

  public init(script: ScriptIndex, segments: [TruthSegment]) {
    self.script = script
    self.segments = segments.sorted { $0.start < $1.start }
  }

  public func spokenPosition(at time: Double) -> Int {
    var spoken = -1
    for segment in segments where segment.start <= time {
      if let inside = position(in: segment, at: time) { spoken = inside }
    }
    return spoken
  }

  /// Last script token spoken inside `segment` by `time`, or nil before its first word ends.
  public func position(in segment: TruthSegment, at time: Double) -> Int? {
    guard segment.kind == .speech, let first = segment.scriptFirst, let last = segment.scriptLast,
      time >= segment.start
    else { return nil }
    if time >= segment.end { return last }
    let weights = (first...last).map { TruthSegment.weight(of: script.tokens[$0].text) }
    let total = weights.reduce(0, +)
    let fraction = (time - segment.start) / (segment.end - segment.start)
    var cumulative = 0.0
    var position: Int?
    for (offset, weight) in weights.enumerated() {
      cumulative += weight
      guard cumulative / total <= fraction + 1e-9 else { break }
      position = first + offset
    }
    return position
  }

  public func kind(at time: Double) -> TruthSegment.Kind {
    segments.last { $0.start <= time && time < $0.end }?.kind ?? .silence
  }
}

public struct Recovery: Sendable, Codable, Equatable {
  public var at: Double
  public var fromToken: Int
  public var toToken: Int
  /// Seconds until the display is within the recovery tolerance; nil if never.
  public var seconds: Double?
  /// Script words spoken in the new place before recovery.
  public var words: Int?
}

public struct Evaluation: Sendable, Codable, Equatable {
  public var speechSamples: Int
  public var medianAbsError: Double
  public var p95AbsError: Double
  public var maxAbsError: Double
  public var meanSignedError: Double
  /// Largest display lead over the true spoken position, any time.
  public var maxOvershoot: Double
  /// Largest display lead over the furthest script token spoken so far. Positive values mean
  /// the display moved to text nobody has read yet.
  public var maxAheadOfFurthest: Double
  /// Largest display lead during silence or ad-lib, and display distance moved there while
  /// already at or past the true position.
  public var maxQuietOvershoot: Double
  public var quietFalseMotion: Double
  /// Error just before the next segment for speech segments followed by at least 1 s of quiet.
  public var settledErrors: [Double]
  /// Seconds from each speech segment's exact end until the display first reaches its last
  /// token; nil entries never got there (skipped, repeated over, or lost).
  public var segmentEndLatencies: [Double?]
  public var recoveries: [Recovery]
  public var backwardMotions: Int
  public var jumps: Int
  public var lostSeconds: Double
  public var tentativeSeconds: Double
  public var revisions: Int
}

public enum Evaluator {
  /// Word-level edit distance divided by reference length, over normalized words.
  public static func wordErrorRate(reference: [String], hypothesis: [String]) -> Double {
    guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
    var previous = Array(0...hypothesis.count)
    for i in 1...reference.count {
      var current = [i] + Array(repeating: 0, count: hypothesis.count)
      for j in stride(from: 1, through: hypothesis.count, by: 1) {
        let cost = reference[i - 1] == hypothesis[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
      }
      previous = current
    }
    return Double(previous[hypothesis.count]) / Double(reference.count)
  }

  /// Normalized words a take actually spoke: script tokens of speech segments plus ad-libs.
  public static func spokenWords(_ truth: GroundTruth) -> [String] {
    truth.segments.flatMap { segment -> [String] in
      switch segment.kind {
      case .speech:
        guard let first = segment.scriptFirst, let last = segment.scriptLast else { return [] }
        return (first...last).map { truth.script.tokens[$0].text }
      case .adlib: return Tokenizer.tokens(in: segment.text).map(\.text)
      case .silence: return []
      }
    }
  }

  public static func evaluate(
    _ result: ReplayResult, truth: GroundTruth, recoveryTolerance: Double = 2, step: Double = 0.05
  ) -> Evaluation {
    var speechErrors: [Double] = []
    var signed = 0.0
    var maxOvershoot = -Double.infinity
    var quietOvershoot = -Double.infinity
    var quietMotion = 0.0
    var backward = 0
    var lost = 0.0
    var tentative = 0.0
    var previous: ReplaySample?
    var furthest = -1.0
    var aheadOfFurthest = -Double.infinity
    for sample in result.samples {
      let spoken = Double(truth.spokenPosition(at: sample.time))
      furthest = max(furthest, spoken)
      aheadOfFurthest = max(aheadOfFurthest, sample.display - furthest)
      let error = sample.display - spoken
      maxOvershoot = max(maxOvershoot, error)
      switch truth.kind(at: sample.time) {
      case .speech:
        speechErrors.append(abs(error))
        signed += error
      case .adlib, .silence:
        quietOvershoot = max(quietOvershoot, error)
        if let previous, sample.display > previous.display, sample.display > spoken {
          quietMotion += sample.display - max(previous.display, spoken)
        }
      }
      if let previous, sample.display < previous.display - 1e-9,
        !result.manualTimes.contains(where: { $0 > previous.time && $0 <= sample.time })
      {
        backward += 1
      }
      if sample.confidence == .lost { lost += step }
      if sample.confidence == .tentative { tentative += step }
      previous = sample
    }
    let sorted = speechErrors.sorted()
    func percentile(_ p: Double) -> Double {
      guard !sorted.isEmpty else { return 0 }
      return sorted[min(sorted.count - 1, Int((p * Double(sorted.count - 1)).rounded()))]
    }
    let speech = truth.segments.filter { $0.kind == .speech }
    var settled: [Double] = []
    for segment in speech {
      guard
        let next = truth.segments.first(where: {
          $0.start >= segment.end - 1e-9 && $0.kind == .speech
        })
      else { continue }
      let quiet = next.start - segment.end
      guard quiet >= 1, let last = segment.scriptLast,
        let sample = result.samples.last(where: { $0.time < next.start })
      else { continue }
      settled.append(sample.display - Double(last))
    }
    let segmentEndLatencies: [Double?] = speech.map { segment in
      guard let last = segment.scriptLast else { return nil }
      return result.samples.first { $0.time >= segment.start && $0.display >= Double(last) - 1e-9 }
        .map { $0.time - segment.end }
    }
    var recoveries: [Recovery] = []
    for (index, segment) in speech.enumerated() where index > 0 {
      guard let first = segment.scriptFirst, let previousLast = speech[index - 1].scriptLast,
        first != previousLast + 1
      else { continue }
      let hit = result.samples.lazy.compactMap { sample -> (Double, Int)? in
        guard let spoken = truth.position(in: segment, at: sample.time),
          abs(sample.display - Double(spoken)) <= recoveryTolerance
        else { return nil }
        return (sample.time, spoken)
      }.first
      recoveries.append(
        Recovery(
          at: segment.start, fromToken: previousLast, toToken: first,
          seconds: hit.map { $0.0 - segment.start },
          words: hit.map { $0.1 - first + 1 }))
    }
    let jumps = result.decisions.filter {
      if case .jump = $0.decision { return true } else { return false }
    }
    return Evaluation(
      speechSamples: sorted.count, medianAbsError: percentile(0.5), p95AbsError: percentile(0.95),
      maxAbsError: sorted.last ?? 0,
      meanSignedError: sorted.isEmpty ? 0 : signed / Double(sorted.count),
      maxOvershoot: maxOvershoot.isFinite ? maxOvershoot : 0,
      maxAheadOfFurthest: aheadOfFurthest.isFinite ? aheadOfFurthest : 0,
      maxQuietOvershoot: quietOvershoot.isFinite ? quietOvershoot : 0,
      quietFalseMotion: quietMotion,
      settledErrors: settled, segmentEndLatencies: segmentEndLatencies, recoveries: recoveries,
      backwardMotions: backward, jumps: jumps.count,
      lostSeconds: lost, tentativeSeconds: tentative, revisions: result.revisions)
  }
}
