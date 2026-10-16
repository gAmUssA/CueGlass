import Foundation

/// One TextKit 2 line range in UTF-16 source coordinates and its viewport-relative layout Y.
public struct VoiceLine: Equatable, Sendable {
  public let utf16Range: Range<Int>
  public let minY: Double

  public init(utf16Range: Range<Int>, minY: Double) {
    self.utf16Range = utf16Range
    self.minY = minY
  }
}

/// Immutable lookup table rebuilt after a snapshot or TextKit layout change.
public struct VoiceLineTable: Equatable, Sendable {
  public let lines: [VoiceLine]

  public init(lines: [VoiceLine]) {
    self.lines = lines.filter { !$0.utf16Range.isEmpty && $0.minY.isFinite }
      .sorted {
        if $0.utf16Range.lowerBound != $1.utf16Range.lowerBound {
          return $0.utf16Range.lowerBound < $1.utf16Range.lowerBound
        }
        return $0.minY < $1.minY
      }
  }

  /// Returns the Y of the line containing the UTF-16 source offset. Offsets in layout gaps
  /// resolve to the preceding line, which keeps token mapping stable at paragraph boundaries.
  public func y(forUTF16Offset offset: Int) -> Double? {
    guard offset >= 0, !lines.isEmpty else { return nil }
    var low = 0
    var high = lines.count
    while low < high {
      let middle = low + (high - low) / 2
      if lines[middle].utf16Range.lowerBound <= offset {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low == 0 ? nil : lines[low - 1].minY
  }

  public func y(for token: Token) -> Double? {
    y(forUTF16Offset: token.range.lowerBound)
  }
}

/// Monotone generation counter used to discard work produced before a stop or manual override.
public struct VoiceEpoch: Equatable, Sendable {
  public private(set) var value: UInt64 = 0

  public init() {}

  @discardableResult
  public mutating func advance() -> UInt64 {
    value &+= 1
    return value
  }

  public func accepts(_ candidate: UInt64) -> Bool { candidate == value }
}
