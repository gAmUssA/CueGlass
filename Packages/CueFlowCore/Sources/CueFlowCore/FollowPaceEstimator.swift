import Foundation

/// Adjusts the shared scroll glide from confirmed presenter progress. It only accelerates above
/// the operator's configured baseline, follows the measured layout distance with a small lead,
/// smooths changes, and caps the increase so transcriber jitter cannot make the page race ahead.
public struct FollowPaceEstimator: Sendable {
  public let baselineVelocity: Double
  public let maximumVelocity: Double
  public let maximumMultiplier: Double
  public let leadFactor: Double
  public let smoothing: Double

  private var previousPosition: Double?
  private var previousTime: Double?
  private var filteredVelocity: Double?

  public init(
    baselineVelocity: Double, maximumVelocity: Double, maximumMultiplier: Double = 1.4,
    leadFactor: Double = 1.1, smoothing: Double = 0.35
  ) {
    self.baselineVelocity = baselineVelocity.isFinite ? max(0.1, baselineVelocity) : 0.1
    self.maximumVelocity =
      maximumVelocity.isFinite
      ? max(self.baselineVelocity, maximumVelocity) : self.baselineVelocity
    self.maximumMultiplier = maximumMultiplier.isFinite ? max(1, maximumMultiplier) : 1
    self.leadFactor = leadFactor.isFinite ? max(1, leadFactor) : 1
    self.smoothing = smoothing.isFinite ? min(1, max(0, smoothing)) : 0.35
  }

  /// Starts a new cadence window after activation, a jump, or spoken resume.
  public mutating func reset(anchorPosition: Double? = nil, at time: Double? = nil) {
    previousPosition = anchorPosition.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    previousTime = time.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    filteredVelocity = nil
  }

  /// Returns an updated glide velocity only for forward progress with a usable time interval.
  /// A long pause gradually returns the glide to the configured baseline.
  public mutating func observe(position: Double, at time: Double) -> Double? {
    guard position.isFinite, position >= 0, time.isFinite, time >= 0 else { return nil }
    guard let previousPosition, let previousTime else {
      self.previousPosition = position
      self.previousTime = time
      return nil
    }

    let duration = time - previousTime
    let distance = position - previousPosition
    guard duration > 0 else { return nil }
    self.previousPosition = position
    self.previousTime = time
    guard distance > 0 else { return nil }

    let cap = min(maximumVelocity, baselineVelocity * maximumMultiplier)
    if duration > 4 {
      let current = filteredVelocity ?? baselineVelocity
      let eased = current + smoothing * (baselineVelocity - current)
      filteredVelocity = min(cap, max(baselineVelocity, eased))
      return filteredVelocity
    }
    guard duration >= 0.2 else { return nil }

    let measured = distance / duration
    guard measured.isFinite else { return nil }
    let desired = min(cap, max(baselineVelocity, measured * leadFactor))
    let current = filteredVelocity ?? baselineVelocity
    let next = current + smoothing * (desired - current)
    filteredVelocity = min(cap, max(baselineVelocity, next))
    return filteredVelocity
  }
}
