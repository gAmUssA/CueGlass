import Foundation

public enum TimelineError: Error, Equatable { case invalidTime, invalidPosition, invalidVelocity }
public protocol PlaybackClock { func now() -> Double }
public struct ManualClock: PlaybackClock {
  public var seconds: Double
  public init(_ seconds: Double) { self.seconds = seconds }
  public func now() -> Double { seconds }
}
public enum PlaybackDirection: String, Codable, Sendable {
  case forward, reverse
  public var sign: Double { self == .forward ? 1 : -1 }
}
public struct PlaybackTimeline: Sendable, Equatable {
  public private(set) var anchorTime = 0.0, anchorPosition = 0.0, velocity = 40.0
  public private(set) var running = false
  public private(set) var direction = PlaybackDirection.forward
  public private(set) var upperBound: Double?
  /// Optional forward ceiling used by Follow Voice. It is independent of the end bound and
  /// is sampled by the same shared timeline as every other presentation mode.
  public private(set) var voiceCeiling: Double?
  public init() {}
  public func position(at time: Double) throws -> Double {
    guard time.isFinite, time >= anchorTime else { throw TimelineError.invalidTime }
    let value = anchorPosition + (running ? direction.sign * velocity * (time - anchorTime) : 0)
    guard value.isFinite else { throw TimelineError.invalidPosition }
    return min(
      min(upperBound ?? .greatestFiniteMagnitude, voiceCeiling ?? .greatestFiniteMagnitude),
      max(0, value))
  }
  public mutating func play(at time: Double) throws {
    try rebase(time)
    running = true
  }
  public mutating func pause(at time: Double) throws {
    try rebase(time)
    running = false
  }
  public mutating func setVelocity(_ speed: Double, at time: Double) throws {
    guard speed.isFinite, (0.1...2000).contains(speed) else { throw TimelineError.invalidVelocity }
    try rebase(time)
    velocity = speed
  }
  public mutating func setDirection(_ next: PlaybackDirection, at time: Double) throws {
    try rebase(time)
    direction = next
  }
  public mutating func setUpperBound(_ bound: Double?, at time: Double) throws {
    if let bound { guard bound.isFinite, bound >= 0 else { throw TimelineError.invalidPosition } }
    try rebase(time)
    upperBound = bound
    anchorPosition = min(bound ?? .greatestFiniteMagnitude, anchorPosition)
    if let voiceCeiling { self.voiceCeiling = min(bound ?? .greatestFiniteMagnitude, voiceCeiling) }
  }
  /// Rebase the existing timeline toward a confirmed script position. A target behind the
  /// current position cannot reverse motion; confirmed rereads use `seek` before setting a new
  /// ceiling.
  public mutating func setVoiceCeiling(_ target: Double, at time: Double) throws {
    guard target.isFinite, target >= 0 else { throw TimelineError.invalidPosition }
    let current = try position(at: time)
    anchorPosition = current
    anchorTime = time
    voiceCeiling = min(upperBound ?? .greatestFiniteMagnitude, max(current, target))
  }
  public mutating func clearVoiceCeiling(at time: Double) throws {
    try rebase(time)
    voiceCeiling = nil
  }
  public mutating func seek(to value: Double, at time: Double) throws {
    guard value.isFinite else { throw TimelineError.invalidPosition }
    guard time.isFinite, time >= anchorTime else { throw TimelineError.invalidTime }
    anchorPosition = min(upperBound ?? .greatestFiniteMagnitude, max(0, value))
    anchorTime = time
    voiceCeiling = nil
  }
  public func boundReached(at time: Double) throws -> Bool {
    let p = try position(at: time)
    return direction == .reverse ? p <= 0 : upperBound.map { p >= $0 } ?? false
  }
  private mutating func rebase(_ time: Double) throws {
    let p = try position(at: time)
    anchorPosition = p
    anchorTime = time
  }
}
public enum StallPolicy {
  public static let threshold = 0.5
  public static func shouldPause(previous: Double?, target: Double) -> Bool {
    previous.map { target - $0 > threshold } ?? false
  }
  public static func effectiveTime(now: Double, presented: Double?) -> Double {
    max(now, presented ?? now)
  }
}
