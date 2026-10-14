import Foundation

/// A normalized word with its UTF-16 offsets in the source text.
public struct Token: Equatable, Sendable, Codable {
  public var text: String
  public var range: Range<Int>

  public init(text: String, range: Range<Int>) {
    self.text = text
    self.range = range
  }
}

public enum Tokenizer {
  private static let numberWords: [String: String] = [
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
    "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12",
    "thirteen": "13", "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
    "eighteen": "18", "nineteen": "19", "twenty": "20",
  ]

  /// Case- and diacritic-folded alphanumerics; number words up to twenty fold to digits so
  /// "three" and "3" compare equal on both the script and the recognizer side.
  public static func normalize(_ word: String) -> String {
    let folded = word.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ).lowercased()
    let kept = String(
      String.UnicodeScalarView(
        folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    return numberWords[kept] ?? kept
  }

  public static func tokens(in text: String) -> [Token] {
    var out: [Token] = []
    let ns = text as NSString
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) {
      word, range, _, _ in
      guard let word else { return }
      let normalized = normalize(word)
      if !normalized.isEmpty {
        out.append(Token(text: normalized, range: range.location..<(range.location + range.length)))
      }
    }
    return out
  }
}

/// Immutable token index over one script revision. Offsets are source offsets, never layout
/// coordinates; a renderer maps token index to on-screen position separately.
public struct ScriptIndex: Sendable {
  public let text: String
  public let tokens: [Token]
  public let paragraphOfToken: [Int]
  public let sentences: [Range<Int>]

  public init(text: String) {
    self.text = text
    tokens = Tokenizer.tokens(in: text)
    let ns = text as NSString
    var paragraph = 0
    var previousEnd = 0
    var paragraphs: [Int] = []
    for token in tokens {
      let gap = ns.substring(
        with: NSRange(location: previousEnd, length: token.range.lowerBound - previousEnd))
      if !paragraphs.isEmpty && gap.contains("\n\n") { paragraph += 1 }
      paragraphs.append(paragraph)
      previousEnd = token.range.upperBound
    }
    paragraphOfToken = paragraphs
    var sentenceRanges: [Range<Int>] = []
    let tokens = self.tokens
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) {
      _, range, _, _ in
      let chars = range.location..<(range.location + range.length)
      let first = tokens.firstIndex { $0.range.lowerBound >= chars.lowerBound }
      let last = tokens.lastIndex { $0.range.upperBound <= chars.upperBound }
      if let first, let last, first <= last { sentenceRanges.append(first..<(last + 1)) }
    }
    sentences = sentenceRanges
  }

  public var count: Int { tokens.count }

  /// Source text covering a token range, used to synthesize fixture audio.
  public func text(of range: Range<Int>) -> String {
    let start = tokens[range.lowerBound].range.lowerBound
    let end = tokens[range.upperBound - 1].range.upperBound
    return (text as NSString).substring(with: NSRange(location: start, length: end - start))
  }
}

/// Benign script written for this experiment. Paragraphs one and three share the phrase
/// "the harbor light" so alignment must disambiguate repeated script phrases.
public enum DemoScript {
  public static let text = """
    Every evening the keeper climbed the narrow stairs to wake the harbor light. \
    She carried a small lantern, a notebook, and a flask of tea. \
    From the top she could see the fishing boats returning across the quiet bay.

    The lamp needed care before it could shine. \
    She polished the heavy lens until every ring of glass was clear. \
    Then she checked the wick, trimmed the edge, and wrote the weather in her notebook.

    When the sun went down, the harbor light turned slowly over the water. \
    Sailors far from shore watched for its steady pattern. \
    They knew that a bright flash every few seconds meant safe passage near the rocks.

    Late at night the wind grew louder and rain tapped against the windows. \
    The keeper stayed awake, listening to the gulls and the distant engines. \
    By morning the storm had passed, and she walked home along the sandy path.
    """
}
