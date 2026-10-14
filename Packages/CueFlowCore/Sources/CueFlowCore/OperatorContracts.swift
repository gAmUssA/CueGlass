import Foundation

public struct SpeedModel: Sendable {
  public let nominalLPM: Double, effectiveLPM: Double, pointsPerSecond: Double
  public var limitedByLayout: Bool { effectiveLPM != nominalLPM }
  public init(lpm: Double, lineAdvance: Double, configuredMax: Double = 240) throws {
    guard lpm.isFinite, lineAdvance.isFinite, lineAdvance > 0, configuredMax.isFinite else {
      throw TimelineError.invalidVelocity
    }
    nominalLPM = min(min(240, max(10, configuredMax)), max(2, lpm))
    pointsPerSecond = min(2000, max(0.1, nominalLPM * lineAdvance / 60))
    effectiveLPM = pointsPerSecond * 60 / lineAdvance
  }
  public func estimatedWPM(words: Int, lines: Int) -> Double? {
    lines > 0 ? effectiveLPM * Double(words) / Double(lines) : nil
  }
}
public enum TimedScrollError: Error, LocalizedError, Equatable {
  case invalidDuration, endUnknown, atEnd, unrepresentable
  case tooFast(Double, Double)
  case tooSlow
  public var errorDescription: String? {
    switch self {
    case .invalidDuration: "Choose a duration greater than zero and no more than 10 hours."
    case .endUnknown: "Measuring script length — try Timed Scrolling when measurement finishes."
    case .atEnd: "Already at the end. Restart or seek back before setting a duration."
    case .unrepresentable:
      "This script and duration exceed the safe calculation range. Choose a shorter script or adjust the reading position."
    case .tooSlow: "This duration needs less than 2 lines/min. Choose a shorter duration."
    case .tooFast(let needed, let maximum):
      "Needs \(Self.integerText(needed, roundUp: true)) lines/min; maximum is \(Self.integerText(maximum)). Choose a longer duration."
    }
  }
  private static func integerText(_ value: Double, roundUp: Bool = false) -> String {
    guard value.isFinite else { return "outside the supported range" }
    let rounded = roundUp ? ceil(value) : value.rounded()
    if rounded >= Double(Int.max) { return ">\(Int.max)" }
    if rounded <= Double(Int.min) { return "<\(Int.min)" }
    return String(Int(rounded))
  }
}
public enum TimedScrollSolver {
  public static func solve(
    position: Double, end: Double?, seconds: Double, lineAdvance: Double, maximum: Double
  ) throws -> Double {
    guard seconds.isFinite, seconds > 0, seconds <= 36000 else {
      throw TimedScrollError.invalidDuration
    }
    guard let end else { throw TimedScrollError.endUnknown }
    guard position.isFinite, end.isFinite, lineAdvance.isFinite, lineAdvance > 0,
      maximum.isFinite, maximum > 0
    else { throw TimedScrollError.invalidDuration }
    guard end > position else { throw TimedScrollError.atEnd }
    let distance = end - position
    let availableAdvance = seconds * lineAdvance
    let needed = distance * 60 / availableAdvance
    let limit = min(maximum, 2000 * 60 / lineAdvance)
    guard distance.isFinite, availableAdvance.isFinite, needed.isFinite, limit.isFinite else {
      throw TimedScrollError.unrepresentable
    }
    guard needed <= limit else { throw TimedScrollError.tooFast(needed, limit) }
    let pointsPerSecond = needed * lineAdvance / 60
    guard pointsPerSecond.isFinite else { throw TimedScrollError.unrepresentable }
    guard needed >= 2, pointsPerSecond >= 0.1 else { throw TimedScrollError.tooSlow }
    return needed
  }
}
public struct ElapsedClock: Sendable {
  private var accumulated = 0.0, began: Double?
  public init() {}
  public mutating func play(at time: Double) { if began == nil { began = time } }
  public mutating func pause(at time: Double) {
    if let began { accumulated += max(0, time - began) }
    began = nil
  }
  public func value(at time: Double) -> Double {
    accumulated + (began.map { max(0, time - $0) } ?? 0)
  }
}
public struct ScrubGate: Sendable {
  private var latched = false
  public init() {}
  public mutating func play() { latched = false }
  public mutating func accepts(momentum: Bool) -> Bool {
    if !momentum { latched = true }
    return latched
  }
  public static func delta(
    rawY: Double, precise: Bool, lineAdvance: Double, scale: Double, verticalReflection: Bool
  ) -> Double {
    -rawY * (precise ? 1 : lineAdvance) / max(0.001, scale) * (verticalReflection ? -1 : 1)
  }
}
public enum ParagraphIndex {
  public static func starts(in text: String) -> [Int] {
    var result: [Int] = []
    var offset = 0
    for line in text.components(separatedBy: "\n") {
      if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(offset) }
      offset += line.utf16.count + 1
    }
    return result
  }
  public static func target(
    position: Double, starts: [Double], forward: Bool, lineAdvance: Double, end: Double
  ) -> Double {
    let epsilon = lineAdvance * 0.25
    if forward { return starts.first { $0 > position + epsilon } ?? end }
    return starts.last { $0 < position - epsilon } ?? 0
  }
}
public enum FrameClamp {
  public struct Rect: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }
  public static func clamp(_ frame: Rect, to visible: Rect) -> Rect {
    let width = min(max(100, frame.width), visible.width)
    let height = min(max(80, frame.height), visible.height)
    let x = min(max(frame.x, visible.x), visible.x + visible.width - width)
    let y = min(max(frame.y, visible.y), visible.y + visible.height - height)
    return Rect(x: x, y: y, width: width, height: height)
  }
}
public enum Contrast {
  public static func worst(
    text: [Double], background: [Double], windowAlpha: Double, panelAlpha: Double
  ) -> Double {
    func luminance(_ c: [Double]) -> Double {
      zip(c, [0.2126, 0.7152, 0.0722]).reduce(0) { a, p in
        let v = p.0
        return a + p.1 * (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
      }
    }
    return [0.0, 0.5, 1.0].map { backdrop in
      let textAlpha = text.count > 3 ? text[3] : 1
      let panel = panelAlpha * (background.count > 3 ? background[3] : 1)
      let bg = (0..<3).map {
        windowAlpha * panel * background[$0] + (1 - windowAlpha * panel) * backdrop
      }
      let fg = (0..<3).map {
        windowAlpha
          * (textAlpha * text[$0] + (1 - textAlpha)
            * (panel * background[$0] + (1 - panel) * backdrop))
          + (1 - windowAlpha) * backdrop
      }
      let l1 = luminance(fg)
      let l2 = luminance(bg)
      return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }.min() ?? 1
  }
}
