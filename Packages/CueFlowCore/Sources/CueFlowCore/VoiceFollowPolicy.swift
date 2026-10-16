import Foundation

public struct FollowConfig: Sendable, Codable, Equatable {
  /// Most recent recognized words aligned on each update.
  public var tailLength = 8
  /// Local window around the confirmed position: words behind and ahead.
  public var localBack = 3
  public var localForward = 16
  /// Matched words needed to advance locally while locked or tentative.
  public var lockedMinMatches = 2
  public var tentativeMinMatches = 3
  /// Unmatched recent words tolerated in an accepted local alignment while locked.
  public var maxTrailing = 2
  /// Unmatched recent words that degrade confidence.
  public var tentativeAfterMisses = 3
  public var lostAfterMisses = 8
  /// Evidence for a jump outside the local window, or for any reacquisition while lost.
  public var jumpMinMatches = 4
  public var backJumpMinMatches = 6
  public var jumpMaxTrailing = 1
  /// Score margin over the best alignment of the same words elsewhere in the script.
  public var jumpUniquenessMargin = 4
  /// Recognized words below this confidence never match. Words without a reported
  /// confidence (negative) are matched and rely on alignment evidence alone.
  public var minWordConfidence = 0.3
  /// Audio seconds without recognized words before reporting a silence hold.
  public var silenceHoldSeconds = 1.2

  public init() {}
}

public enum FollowConfidence: String, Sendable, Codable {
  case locked, tentative, lost
}

public enum HoldReason: String, Sendable, Codable {
  case silence, mismatch, lowConfidence, lost, suspended
}

public enum FollowDecision: Equatable, Sendable {
  case none
  /// Smooth forward motion to the last confirmed spoken token.
  case advance(to: Int)
  /// Confirmed discontinuity (skip forward or long re-read backward).
  case jump(from: Int, to: Int)
  case hold(HoldReason)
}

/// Incremental script-position tracker. It knows nothing about layout or display timing;
/// position is the index of the last script token confirmed as spoken (-1 before the start).
public struct FollowPolicy: Sendable {
  public let script: ScriptIndex
  public let config: FollowConfig
  public private(set) var position = -1
  public private(set) var confidence = FollowConfidence.locked
  public private(set) var suspended = false
  public private(set) var silent = false
  private var lastWordEnd = 0.0
  private var listeningSince = 0.0
  private var lastHypothesis: [RecognizedWord] = []

  public init(script: ScriptIndex, config: FollowConfig = FollowConfig()) {
    self.script = script
    self.config = config
  }

  public mutating func update(
    hypothesis: [RecognizedWord], allowDiscontinuities: Bool = true,
    reevaluateUnchangedHypothesis: Bool = false
  ) -> FollowDecision {
    guard hypothesis != lastHypothesis || reevaluateUnchangedHypothesis else { return .none }
    lastHypothesis = hypothesis
    let words = hypothesis.filter { $0.start >= listeningSince - 0.0005 }
    guard let latest = words.last else { return .none }
    lastWordEnd = max(lastWordEnd, latest.end)
    silent = false
    guard !suspended else { return .hold(.suspended) }

    let query: [String?] = words.suffix(config.tailLength).map { word in
      let normalized = Tokenizer.normalize(word.text)
      let trusted = word.confidence < 0 || word.confidence >= config.minWordConfidence
      return trusted && !normalized.isEmpty ? normalized : nil
    }
    var misses = query.count
    if confidence != .lost {
      let window = (position - config.localBack)..<(position + 1 + config.localForward)
      if let local = Aligner.align(
        query: query, script: script, window: window, preferEnd: position + 1)
      {
        misses = local.trailingUnmatched
        let locked = confidence == .locked
        let needed = locked ? config.lockedMinMatches : config.tentativeMinMatches
        let trailing = locked ? config.maxTrailing : config.jumpMaxTrailing
        if local.matches >= needed && local.trailingUnmatched <= trailing {
          confidence = .locked
          // Advance only on two adjacent matched words, so one coincidental word inside an
          // ad-lib cannot move the display.
          if local.scriptEnd > position && local.endRun >= 2 {
            position = local.scriptEnd
            return .advance(to: position)
          }
          return .none
        }
      }
    }
    if misses >= config.lostAfterMisses {
      confidence = .lost
    } else if misses >= config.tentativeAfterMisses && confidence == .locked {
      confidence = .tentative
    }
    if let move = reacquire(query: query, allowDiscontinuities: allowDiscontinuities) {
      return move
    }
    if query.suffix(max(misses, 1)).allSatisfy({ $0 == nil }) { return .hold(.lowConfidence) }
    return .hold(confidence == .lost ? .lost : .mismatch)
  }

  private mutating func reacquire(
    query: [String?], allowDiscontinuities: Bool
  ) -> FollowDecision? {
    guard
      let found = Aligner.align(
        query: query, script: script, window: 0..<script.count, preferEnd: position + 1),
      found.matches >= config.jumpMinMatches, found.trailingUnmatched <= config.jumpMaxTrailing,
      found.endRun >= 2, found.score - found.runnerUpScore >= config.jumpUniquenessMargin,
      found.scriptEnd != position
    else { return nil }
    if found.scriptEnd < position && found.matches < config.backJumpMinMatches { return nil }
    let from = position
    let local = found.scriptEnd > from && found.scriptEnd <= from + 1 + config.localForward
    guard local || allowDiscontinuities else { return nil }
    position = found.scriptEnd
    confidence = .locked
    return local ? .advance(to: position) : .jump(from: from, to: position)
  }

  /// Reports a silence hold once no word has ended for `silenceHoldSeconds` of audio time.
  public mutating func tick(now: Double) -> FollowDecision {
    guard !suspended, !silent, now - lastWordEnd >= config.silenceHoldSeconds else { return .none }
    silent = true
    return .hold(.silence)
  }

  public mutating func suspend() { suspended = true }

  /// Explicit re-arm after manual control. Only speech heard after `now` counts, starting
  /// from the operator's position with tentative confidence.
  public mutating func resume(at manualPosition: Int, now: Double) {
    position = min(max(manualPosition, -1), script.count - 1)
    confidence = .tentative
    suspended = false
    silent = false
    listeningSince = now
    lastWordEnd = now
  }
}
