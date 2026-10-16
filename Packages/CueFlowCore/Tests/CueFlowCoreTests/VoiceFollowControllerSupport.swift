import CueFlowCore
import Foundation

public enum PlaybackMode: String, Sendable, Codable {
  case follow, timed
}

/// Operator transport commands. Each one except `resumeFollowing` suspends following.
public enum ManualCommand: Equatable, Sendable {
  case pause
  case scrub(to: Int)
  case step(Int)
  case resumeFollowing
  case setMode(PlaybackMode)
}

/// Simulated display position in script-token units. It stands in for the app timeline:
/// glides forward toward a confirmed target at a bounded rate and moves backward only by seek.
public struct LogicalScroll: Sendable {
  public private(set) var position: Double
  public private(set) var target: Double
  public let maxGlideWordsPerSecond: Double

  public init(position: Double = -1, maxGlideWordsPerSecond: Double = 10) {
    self.position = position
    target = position
    self.maxGlideWordsPerSecond = maxGlideWordsPerSecond
  }

  public mutating func glide(to value: Double) { target = max(target, value) }

  public mutating func seek(to value: Double) {
    position = value
    target = value
  }

  public mutating func stop() { target = position }

  public mutating func advance(by seconds: Double) {
    guard target > position else { return }
    position = min(target, position + maxGlideWordsPerSecond * seconds)
  }
}

/// Event-rate controller: transcript updates and operator commands produce logical scroll
/// commands; nothing here runs per display frame.
public struct FollowController: Sendable {
  public private(set) var policy: FollowPolicy
  public private(set) var scroll: LogicalScroll
  public private(set) var mode = PlaybackMode.follow

  public init(policy: FollowPolicy, scroll: LogicalScroll = LogicalScroll()) {
    self.policy = policy
    self.scroll = scroll
  }

  @discardableResult
  public mutating func ingest(hypothesis: [RecognizedWord]) -> FollowDecision {
    guard mode == .follow else { return .none }
    let decision = policy.update(hypothesis: hypothesis)
    apply(decision)
    return decision
  }

  @discardableResult
  public mutating func tick(now: Double, elapsed: Double) -> FollowDecision {
    scroll.advance(by: elapsed)
    guard mode == .follow else { return .none }
    return policy.tick(now: now)
  }

  public mutating func handle(_ command: ManualCommand, now: Double) {
    let last = Double(policy.script.count - 1)
    switch command {
    case .pause:
      policy.suspend()
      scroll.stop()
    case .scrub(let index):
      policy.suspend()
      scroll.seek(to: min(max(Double(index), -1), last))
    case .step(let delta):
      policy.suspend()
      scroll.seek(to: min(max(scroll.position.rounded() + Double(delta), -1), last))
    case .resumeFollowing:
      guard mode == .follow else { return }
      policy.resume(at: Int(scroll.position.rounded()), now: now)
    case .setMode(let newMode):
      policy.suspend()
      scroll.stop()
      mode = newMode
    }
  }

  private mutating func apply(_ decision: FollowDecision) {
    switch decision {
    case .advance(let index): scroll.glide(to: Double(index))
    case .jump(_, let index): scroll.seek(to: Double(index))
    case .none, .hold: break
    }
  }
}
