import Foundation

/// Best local alignment of a recognized-word query against a script window.
public struct AlignmentCandidate: Equatable, Sendable {
  /// Inclusive script token indices of the first and last matched words.
  public var scriptStart: Int
  public var scriptEnd: Int
  /// Inclusive query indices of the first and last matched words.
  public var queryStart: Int
  public var queryEnd: Int
  public var matches: Int
  public var score: Int
  /// Recent query words after the last matched word.
  public var trailingUnmatched: Int
  /// Best competing score for the same latest query word at a different script location.
  public var runnerUpScore: Int
  /// Consecutive exact-or-near matches, adjacent in both query and script, ending at the end.
  public var endRun: Int
}

public enum WordMatch {
  /// 2 for an exact normalized match, 1 for a near spelling (recognizer variants such as
  /// "harbour"/"harbor"), 0 otherwise.
  public static func score(_ a: String, _ b: String) -> Int {
    if a == b { return 2 }
    let shorter = min(a.count, b.count)
    guard shorter >= 4 else { return 0 }
    let limit = shorter >= 7 ? 2 : 1
    return editDistance(Array(a), Array(b), limit: limit) <= limit ? 1 : 0
  }

  static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
    if abs(a.count - b.count) > limit { return limit + 1 }
    guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
    var previous = Array(0...b.count)
    for i in 1...a.count {
      var current = [i] + Array(repeating: 0, count: b.count)
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
      }
      previous = current
    }
    return previous[b.count]
  }
}

/// Smith–Waterman local alignment over normalized words. A `nil` query word (for example a
/// low-confidence recognition) can never match, so it only adds gap or mismatch cost.
public enum Aligner {
  static let mismatch = -1
  static let gap = -1

  public static func align(
    query: [String?], script: ScriptIndex, window: Range<Int>, preferEnd: Int
  ) -> AlignmentCandidate? {
    let lo = max(0, window.lowerBound)
    let hi = min(script.count, window.upperBound)
    let m = query.count
    let n = hi - lo
    guard m > 0, n > 0 else { return nil }
    let width = n + 1
    var h = Array(repeating: 0, count: (m + 1) * width)
    // 0 stop, 1 diagonal, 2 up (skip query word), 3 left (skip script word)
    var move = Array(repeating: UInt8(0), count: (m + 1) * width)
    var matchedCell = Array(repeating: false, count: (m + 1) * width)
    for i in 1...m {
      for j in 1...n {
        let wordScore =
          query[i - 1].map { WordMatch.score($0, script.tokens[lo + j - 1].text) } ?? 0
        let diagonal = h[(i - 1) * width + j - 1] + (wordScore > 0 ? wordScore : mismatch)
        let up = h[(i - 1) * width + j] + gap
        let left = h[i * width + j - 1] + gap
        var best = 0
        var step: UInt8 = 0
        if diagonal > best { (best, step) = (diagonal, 1) }
        if up > best { (best, step) = (up, 2) }
        if left > best { (best, step) = (left, 3) }
        h[i * width + j] = best
        move[i * width + j] = step
        matchedCell[i * width + j] = step == 1 && wordScore > 0
      }
    }
    // Prefer the highest score, then the most recent query word, then the script location
    // nearest the expected next word.
    var bestCell: (i: Int, j: Int)?
    func better(_ i: Int, _ j: Int, than other: (i: Int, j: Int)) -> Bool {
      let s = h[i * width + j]
      let o = h[other.i * width + other.j]
      if s != o { return s > o }
      if i != other.i { return i > other.i }
      return abs(lo + j - 1 - preferEnd) < abs(lo + other.j - 1 - preferEnd)
    }
    for i in 1...m {
      for j in 1...n where matchedCell[i * width + j] && h[i * width + j] > 0 {
        if bestCell == nil || better(i, j, than: bestCell!) { bestCell = (i, j) }
      }
    }
    guard let end = bestCell else { return nil }
    var i = end.i
    var j = end.j
    var matches = 0
    var endRun = 0
    var runOpen = true
    var start = end
    while i > 0, j > 0, h[i * width + j] > 0 {
      switch move[i * width + j] {
      case 1:
        if matchedCell[i * width + j] {
          matches += 1
          start = (i, j)
          if runOpen { endRun += 1 }
        } else {
          runOpen = false
        }
        i -= 1
        j -= 1
      case 2, 3:
        runOpen = false
        if move[i * width + j] == 2 { i -= 1 } else { j -= 1 }
      default: i = 0
      }
    }
    let exclusion = m + 2
    var runnerUp = 0
    for j in 1...n where abs(j - end.j) > exclusion && matchedCell[end.i * width + j] {
      runnerUp = max(runnerUp, h[end.i * width + j])
    }
    return AlignmentCandidate(
      scriptStart: lo + start.j - 1, scriptEnd: lo + end.j - 1,
      queryStart: start.i - 1, queryEnd: end.i - 1,
      matches: matches, score: h[end.i * width + end.j],
      trailingUnmatched: m - end.i, runnerUpScore: runnerUp, endRun: endRun)
  }
}
