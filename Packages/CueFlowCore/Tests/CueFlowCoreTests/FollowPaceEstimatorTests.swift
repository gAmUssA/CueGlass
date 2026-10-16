import CueFlowCore
import Testing

@Suite struct FollowPaceEstimatorTests {
  @Test func fasterConfirmedDeliveryRaisesGlideGraduallyWithinTheConfiguredBound() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 0, at: 0)

    let first = estimator.observe(position: 40, at: 1)
    let second = estimator.observe(position: 120, at: 2)

    #expect(first != nil && first! > 40)
    #expect(second != nil && second! > first!)
    #expect(second! <= 56)
  }

  @Test func slowDeliveryNeverSlowsBelowTheOperatorBaseline() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 0, at: 0)

    #expect(estimator.observe(position: 8, at: 1) == 40)
  }

  @Test func longPauseEasesBackTowardBaseline() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 0, at: 0)
    _ = estimator.observe(position: 80, at: 1)
    let afterPause = estimator.observe(position: 81, at: 7)

    #expect(afterPause != nil && afterPause! >= 40 && afterPause! < 56)
  }

  @Test func invalidAndBackwardObservationsDoNotCreateAcceleration() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 80, at: 2)

    #expect(estimator.observe(position: 20, at: 3) == nil)
    #expect(estimator.observe(position: .infinity, at: 4) == nil)
    #expect(estimator.observe(position: 160, at: 1) == nil)
    let recovery = estimator.observe(position: 100, at: 5)
    #expect(recovery != nil && recovery! >= 40 && recovery! < 42)
  }

  @Test func sameLineWordsKeepTheAnchorUntilAUsableLineChange() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 0, at: 0)

    #expect(estimator.observe(position: 0, at: 1) == nil)
    #expect(estimator.observe(position: 0, at: 2) == nil)
    #expect(estimator.observe(position: 80, at: 3) == 40)
  }

  @Test func subThresholdSamplesAccumulateFromTheLastUsableAnchor() {
    var estimator = FollowPaceEstimator(baselineVelocity: 40, maximumVelocity: 240)
    estimator.reset(anchorPosition: 0, at: 0)

    #expect(estimator.observe(position: 20, at: 0.1) == nil)
    #expect(estimator.observe(position: 40, at: 0.15) == nil)
    let speed = estimator.observe(position: 80, at: 0.25)

    #expect(speed != nil && speed! > 40 && speed! <= 56)
  }
}
