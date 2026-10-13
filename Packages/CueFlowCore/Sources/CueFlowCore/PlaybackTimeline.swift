import Foundation

public enum TimelineError: Error, Equatable { case invalidTime, invalidPosition, invalidVelocity }
public protocol PlaybackClock { func now() -> Double }
public struct ManualClock: PlaybackClock {
  public var seconds: Double
  public init(_ seconds: Double) { self.seconds = seconds }
  public func now() -> Double { seconds }
}

/// Host-media-time seconds only. Sampling is pure and independent of frame rate.
public struct PlaybackTimeline: Sendable, Equatable {
  public private(set) var anchorTime: Double = 0
  public private(set) var anchorPosition: Double = 0
  public private(set) var velocity: Double = 40
  public private(set) var running = false
  public init() {}
  public func position(at time: Double) throws -> Double {
    guard time.isFinite, time >= anchorTime else { throw TimelineError.invalidTime }
    let value = anchorPosition + (running ? velocity * (time - anchorTime) : 0)
    guard value.isFinite else { throw TimelineError.invalidPosition }
    return value
  }
  public mutating func play(at time: Double) throws {
    try rebase(at: time)
    running = true
  }
  public mutating func pause(at time: Double) throws {
    try rebase(at: time)
    running = false
  }
  public mutating func setVelocity(_ value: Double, at time: Double) throws {
    guard value.isFinite, (1...300).contains(value) else { throw TimelineError.invalidVelocity }
    try rebase(at: time)
    velocity = value
  }
  public mutating func seek(to position: Double, at time: Double) throws {
    guard position.isFinite, position >= 0 else { throw TimelineError.invalidPosition }
    guard time.isFinite, time >= anchorTime else { throw TimelineError.invalidTime }
    anchorPosition = position
    anchorTime = time
  }
  private mutating func rebase(at time: Double) throws {
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
