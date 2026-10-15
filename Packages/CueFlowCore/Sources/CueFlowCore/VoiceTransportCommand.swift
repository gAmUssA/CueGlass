import Foundation

/// A transport action spoken while Follow Voice is actively listening.
public enum VoiceTransportCommand: String, Equatable, Sendable {
  case pause
  case resume
  case stopFollowing
  case stopTake
}

/// Recognizes short, prefixed transport phrases from stable speech results. It buffers at most
/// four normalized words per channel, one possible command and audio times; it never stores a
/// transcript. A command fires at the finalization watermark or after unchanged wording remains
/// stable briefly. Known low-confidence words are rejected; missing confidence is treated as
/// unknown.
public struct VoiceTransportCommandMatcher: Sendable {
  private struct Word: Sendable {
    let text: String
    let start: Double
    let end: Double
  }

  private struct Candidate: Sendable {
    let command: VoiceTransportCommand
    let start: Double
    let end: Double
    let wordCount: Int
    let firstSeenAt: Double
    let awaitsContinuation: Bool
    let commandOnly: Bool
  }

  private var pending: [Word] = []
  /// DictationTranscriber can publish the wake phrase and its command in separate updates.
  /// Keep the three best command-only hypotheses in separate rolling windows. None can feed
  /// script alignment or be combined with words from a different interpretation.
  private var commandOnlyPending: [[Word]] = [[], [], []]
  private var candidate: Candidate?
  private var scriptFinalizedThrough = -Double.infinity
  private var commandFinalizedThrough = -Double.infinity
  private var consumedThrough = -Double.infinity
  public private(set) var lastResolvedAudioTime: Double?
  private let enabled: Bool

  private static let minimumConfidence = 0.55
  private static let maximumWordGap = 1.1
  private static let maximumPhraseDuration = 2.5
  private static let confirmationInterval = 0.75
  private static let epsilon = 0.0005

  public init(enabled: Bool = true) {
    self.enabled = enabled
  }

  public var hasPendingCandidate: Bool { candidate != nil }

  public mutating func consume(
    _ event: TranscriptEvent, at observationTime: Double = ProcessInfo.processInfo.systemUptime
  ) -> VoiceTransportCommand? {
    guard enabled else { return nil }
    let now = observationTime.isFinite ? observationTime : ProcessInfo.processInfo.systemUptime
    let commandOnly = event.isCommandOnly == true

    if let watermark = event.finalizedThrough, watermark.isFinite {
      if commandOnly {
        commandFinalizedThrough = max(commandFinalizedThrough, watermark)
      } else {
        scriptFinalizedThrough = max(scriptFinalizedThrough, watermark)
      }
    }
    if event.isFinal, event.rangeEnd.isFinite {
      if commandOnly {
        commandFinalizedThrough = max(commandFinalizedThrough, event.rangeEnd)
      } else {
        scriptFinalizedThrough = max(scriptFinalizedThrough, event.rangeEnd)
      }
    }

    let previousCandidate = candidate
    var invalidatedCandidate = false
    let hasHypotheses = !event.words.isEmpty || !(event.commandAlternatives ?? []).isEmpty
    if event.rangeStart.isFinite, hasHypotheses {
      // A revision to a candidate's audio range invalidates it. Preserve any earlier prefix when
      // the next result only replaces the command tail.
      if commandOnly {
        let hypotheses = event.commandAlternatives ?? []
        for index in commandOnlyPending.indices {
          commandOnlyPending[index].removeAll {
            $0.start >= event.rangeStart - Self.epsilon
          }
          if hypotheses.indices.contains(index) {
            commandOnlyPending[index].append(contentsOf: normalizedWords(in: hypotheses[index]))
          }
          if commandOnlyPending[index].count > 4 {
            commandOnlyPending[index].removeFirst(commandOnlyPending[index].count - 4)
          }
        }
      } else {
        pending.removeAll { $0.start >= event.rangeStart - Self.epsilon }
        pending.append(contentsOf: normalizedWords(in: event.words))
        if pending.count > 4 { pending.removeFirst(pending.count - 4) }
      }
      if let candidate, candidate.commandOnly == commandOnly,
        candidate.end > event.rangeStart + Self.epsilon
      {
        self.candidate = nil
        invalidatedCandidate = true
      }

      // SpeechTranscriber's best transcript can mishear a product name while a lower-ranked
      // alternative gets it right. Consider those alternatives only for commands.
      let alternativeCandidate: Candidate? =
        commandOnly
        ? nil
        : (event.commandAlternatives ?? []).prefix(3).compactMap { hypothesis -> Candidate? in
          Self.findCandidate(
            in: Array(normalizedWords(in: hypothesis).suffix(4)), at: now, commandOnly: false)
        }.first
      let primaryCandidate: Candidate?
      if commandOnly {
        primaryCandidate =
          commandOnlyPending.compactMap {
            Self.findCandidate(in: $0, at: now, commandOnly: true)
          }.first
      } else {
        primaryCandidate = Self.findCandidate(in: pending, at: now, commandOnly: false)
      }
      if let found = primaryCandidate ?? alternativeCandidate {
        if let previousCandidate, Self.samePhrase(previousCandidate, found) {
          candidate = Candidate(
            command: found.command, start: found.start, end: found.end,
            wordCount: found.wordCount, firstSeenAt: previousCandidate.firstSeenAt,
            awaitsContinuation: found.awaitsContinuation, commandOnly: found.commandOnly)
        } else {
          candidate = found
        }
      } else if invalidatedCandidate {
        candidate = nil
      }
    }

    return resolveCandidate(at: now)
  }

  /// Advances stable-phrase confirmation while speech results are quiet.
  public mutating func advance(to observationTime: Double) -> VoiceTransportCommand? {
    resolveCandidate(at: observationTime)
  }

  public mutating func clear() {
    pending.removeAll(keepingCapacity: false)
    commandOnlyPending = [[], [], []]
    candidate = nil
    scriptFinalizedThrough = -Double.infinity
    commandFinalizedThrough = -Double.infinity
    consumedThrough = -Double.infinity
    lastResolvedAudioTime = nil
  }

  private func normalizedWords(in words: [RecognizedWord]) -> [Word] {
    words.compactMap { word in
      guard word.start.isFinite, word.end.isFinite, word.end >= word.start,
        word.end > consumedThrough + Self.epsilon
      else { return nil }
      let normalized = Tokenizer.normalize(word.text)
      guard !normalized.isEmpty else { return nil }
      if word.confidence.isFinite, word.confidence >= 0,
        word.confidence < Self.minimumConfidence
      {
        return nil
      }
      return Word(text: normalized, start: word.start, end: word.end)
    }
  }

  private mutating func resolveCandidate(at now: Double) -> VoiceTransportCommand? {
    guard enabled, now.isFinite, let candidate else { return nil }
    let stable =
      now >= candidate.firstSeenAt
      && now - candidate.firstSeenAt >= Self.confirmationInterval
    let finalizedThrough = candidate.commandOnly ? commandFinalizedThrough : scriptFinalizedThrough
    let finalized = candidate.end <= finalizedThrough + Self.epsilon
    guard stable || (finalized && !candidate.awaitsContinuation) else { return nil }

    consumedThrough = candidate.end
    lastResolvedAudioTime = candidate.end
    pending.removeAll { $0.end <= consumedThrough + Self.epsilon }
    commandOnlyPending = commandOnlyPending.map {
      $0.filter { $0.end > consumedThrough + Self.epsilon }
    }
    self.candidate = nil
    return candidate.command
  }

  private static func samePhrase(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    lhs.command == rhs.command && lhs.commandOnly == rhs.commandOnly
      && lhs.wordCount == rhs.wordCount
      && abs(lhs.start - rhs.start) <= epsilon && abs(lhs.end - rhs.end) <= epsilon
  }

  private static func findCandidate(
    in words: [Word], at now: Double, commandOnly: Bool
  ) -> Candidate? {
    var found: Candidate?
    for endIndex in words.indices {
      for length in [4, 3, 2] where endIndex + 1 >= length {
        let phrase = Array(words[(endIndex - length + 1)...endIndex])
        guard let first = phrase.first, let last = phrase.last,
          last.end - first.start <= maximumPhraseDuration,
          zip(phrase, phrase.dropFirst()).allSatisfy({
            $1.start >= $0.start - epsilon && $1.start - $0.start <= maximumWordGap
          }),
          let command = command(for: phrase.map(\.text))
        else { continue }

        let candidate = Candidate(
          command: command, start: first.start, end: last.end, wordCount: phrase.count,
          firstSeenAt: now,
          awaitsContinuation: command == .stopFollowing && phrase.count == 2
            && phrase.map(\.text) == ["cueglass", "stop"]
            || command == .stopFollowing && phrase.count == 3
              && phrase.map(\.text) == ["cue", "glass", "stop"]
            || command == .stopFollowing && phrase.count == 2
              && phrase.map(\.text) == ["prompter", "stop"],
          commandOnly: commandOnly
        )
        if let current = found {
          if candidate.end > current.end + epsilon
            || abs(candidate.end - current.end) <= epsilon
              && candidate.wordCount > current.wordCount
          {
            found = candidate
          }
        } else {
          found = candidate
        }
      }
    }
    return found
  }

  private static func command(for words: [String]) -> VoiceTransportCommand? {
    switch words {
    case ["cueglass", "pause"]: .pause
    case ["cue", "glass", "pause"]: .pause
    case ["prompter", "pause"]: .pause
    case ["cueglass", "resume"]: .resume
    case ["cue", "glass", "resume"]: .resume
    case ["prompter", "resume"]: .resume
    case ["cueglass", "stop"]: .stopFollowing
    case ["cue", "glass", "stop"]: .stopFollowing
    case ["prompter", "stop"]: .stopFollowing
    case ["cueglass", "stop", "following"]: .stopFollowing
    case ["cue", "glass", "stop", "following"]: .stopFollowing
    case ["prompter", "stop", "following"]: .stopFollowing
    case ["cueglass", "stop", "take"]: .stopTake
    case ["cue", "glass", "stop", "take"]: .stopTake
    case ["prompter", "stop", "take"]: .stopTake
    default: nil
    }
  }
}
