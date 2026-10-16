import Foundation

/// One recognized word with its audio-time span (seconds from the start of the take).
/// A negative confidence means the recognizer reported none (observed for volatile results).
public struct RecognizedWord: Equatable, Sendable, Codable {
  public var text: String
  public var start: Double
  public var end: Double
  public var confidence: Double

  public init(text: String, start: Double, end: Double, confidence: Double = 1) {
    self.text = text
    self.start = start
    self.end = end
    self.confidence = confidence
  }
}

/// A transcriber result as the follower sees it. `availableAt` is on the audio clock: the take
/// time at which the result reached the app (measured arrival for real-time replay).
public struct TranscriptEvent: Equatable, Sendable, Codable {
  public var isFinal: Bool
  public var rangeStart: Double
  public var rangeEnd: Double
  public var availableAt: Double
  public var words: [RecognizedWord]
  /// Up to a few alternative interpretations used only to recover prefixed transport commands.
  /// Script alignment always consumes `words`, the recognizer's best interpretation.
  public var commandAlternatives: [[RecognizedWord]]?
  /// Marks results from the command-only recognition channel so they never enter script alignment.
  public var isCommandOnly: Bool?
  /// Audio time before which this transcriber has finalized every result. Volatile wording may
  /// remain unchanged and never be reissued as a final result, so consumers that need stable
  /// speech can use this watermark instead of waiting for `isFinal` on the same phrase.
  public var finalizedThrough: Double?

  public init(
    isFinal: Bool, rangeStart: Double, rangeEnd: Double, availableAt: Double,
    words: [RecognizedWord], finalizedThrough: Double? = nil,
    commandAlternatives: [[RecognizedWord]] = [], isCommandOnly: Bool = false
  ) {
    self.isFinal = isFinal
    self.rangeStart = rangeStart
    self.rangeEnd = rangeEnd
    self.availableAt = availableAt
    self.words = words
    self.finalizedThrough = finalizedThrough
    self.commandAlternatives = commandAlternatives
    self.isCommandOnly = isCommandOnly
  }
}

/// Merges volatile and final results into one current hypothesis. Final words are never
/// replaced; a volatile result replaces earlier volatile words from its range start onward.
public struct TranscriptAccumulator: Sendable {
  public private(set) var finalized: [RecognizedWord] = []
  public private(set) var volatile: [RecognizedWord] = []
  /// Count of volatile updates that changed an already-shown word's text.
  public private(set) var revisions = 0

  private static let epsilon = 0.0005
  /// Only the most recent words are needed for alignment. A long speech take must not keep
  /// accumulating recognized words in memory.
  public static let retainedWordLimit = 96

  public init() {}

  public var hypothesis: [RecognizedWord] { finalized + volatile }

  public mutating func apply(_ event: TranscriptEvent) {
    if event.isFinal {
      countRevisions(
        replacing: volatile.filter { $0.start < event.rangeEnd - Self.epsilon }, with: event.words)
      volatile.removeAll { $0.start < event.rangeEnd - Self.epsilon }
      appendFinalized(event.words)
    } else {
      countRevisions(
        replacing: volatile.filter { $0.start >= event.rangeStart - Self.epsilon },
        with: event.words)
      volatile.removeAll { $0.start >= event.rangeStart - Self.epsilon }
      volatile.append(
        contentsOf: event.words.filter { $0.start >= (finalized.last?.end ?? 0) - Self.epsilon })
    }

    let watermark = max(
      event.finalizedThrough ?? -Double.infinity,
      event.isFinal ? event.rangeEnd : -Double.infinity)
    if watermark.isFinite {
      let newlyFinalized = volatile.filter { $0.end <= watermark + Self.epsilon }
      appendFinalized(newlyFinalized)
      volatile.removeAll { $0.end <= watermark + Self.epsilon }
    }
    if finalized.count > Self.retainedWordLimit {
      finalized.removeFirst(finalized.count - Self.retainedWordLimit)
    }
    if volatile.count > Self.retainedWordLimit {
      volatile.removeFirst(volatile.count - Self.retainedWordLimit)
    }
  }

  public mutating func clear() {
    finalized.removeAll(keepingCapacity: false)
    volatile.removeAll(keepingCapacity: false)
    revisions = 0
  }

  private mutating func countRevisions(replacing old: [RecognizedWord], with new: [RecognizedWord])
  {
    for word in old {
      let overlapping = new.first { $0.start < word.end && $0.end > word.start }
      if let overlapping, Tokenizer.normalize(overlapping.text) != Tokenizer.normalize(word.text) {
        revisions += 1
      }
    }
  }

  private mutating func appendFinalized(_ words: [RecognizedWord]) {
    // Compare every incoming word with the state from before this batch. Speech can put several
    // word attributes on the same audio range; appending the first one must not suppress the rest.
    let previouslyFinalized = finalized
    for word in words
    where !previouslyFinalized.contains(where: {
      $0.start < word.end - Self.epsilon && $0.end > word.start + Self.epsilon
    }) {
      finalized.append(word)
    }
  }
}
