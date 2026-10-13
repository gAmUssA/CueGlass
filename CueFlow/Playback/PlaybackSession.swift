import AppKit
import CueFlowCore
import QuartzCore

struct ScriptSnapshot {
  let id: UUID
  let documentID: UUID
  let revision: Int
  let attributed: NSAttributedString
}
@MainActor final class PlaybackSession {
  enum State { case idle, paused, running }
  private(set) var snapshot: ScriptSnapshot?
  private(set) var timeline = PlaybackTimeline()
  private(set) var state: State = .idle
  private(set) var lastPresentedTarget: Double?
  var pendingRevision = false
  var style = ReadingStyle()
  var logicalSize = CGSize(width: 1280, height: 720)
  var message = "Ready"
  var onChange: (() -> Void)?
  var clock: () -> Double = { CACurrentMediaTime() }
  var effectiveTime: Double {
    StallPolicy.effectiveTime(now: clock(), presented: lastPresentedTarget)
  }
  func prepare(_ doc: ScriptDocument) throws {
    guard state == .idle else { return }
    guard doc.cloudStatus != .notDownloaded, doc.cloudStatus != .downloading else {
      throw CocoaError(.fileReadUnknown)
    }
    snapshot = ScriptSnapshot(
      id: UUID(), documentID: doc.model.documentID, revision: doc.revision,
      attributed: doc.source.copy() as! NSAttributedString)
    style = doc.model.readingStyle
    timeline = PlaybackTimeline()
    try timeline.setVelocity(doc.model.preferredSpeedPointsPerSecond, at: clock())
    state = .paused
    pendingRevision = false
    message = "Paused"
  }
  func toggle(_ doc: ScriptDocument) throws {
    try prepare(doc)
    if state == .running {
      try pause()
    } else {
      try timeline.play(at: effectiveTime)
      lastPresentedTarget = effectiveTime
      state = .running
      message = "Playing"
      onChange?()
    }
  }
  func pause() throws {
    guard state != .idle else { return }
    try timeline.pause(at: effectiveTime)
    state = .paused
    message = "Paused"
    onChange?()
  }
  func pauseSafely(_ reason: String) throws {
    guard state != .idle else { return }
    try timeline.pause(at: max(timeline.anchorTime, lastPresentedTarget ?? effectiveTime))
    state = .paused
    message = reason
    onChange?()
  }
  func stop() {
    timeline = PlaybackTimeline()
    snapshot = nil
    state = .idle
    lastPresentedTarget = nil
    pendingRevision = false
    message = "Stopped — editing enabled"
    onChange?()
  }
  func speed(_ value: Double) throws {
    try timeline.setVelocity(value, at: effectiveTime)
    onChange?()
  }
  func seek(_ position: Double) throws {
    try timeline.seek(to: position, at: effectiveTime)
    lastPresentedTarget = nil
    onChange?()
  }
  func changed(_ doc: ScriptDocument) {
    if let snapshot, snapshot.revision != doc.revision {
      pendingRevision = true
      message = "Newer version available — pause and Load Latest"
      onChange?()
    }
  }
  func loadLatest(_ doc: ScriptDocument) throws {
    guard state != .running else { throw CocoaError(.validationMissingMandatoryProperty) }
    let old = snapshot?.attributed.string ?? ""
    let oldPosition = try timeline.position(at: effectiveTime)
    stop()
    try prepare(doc)
    if old == snapshot?.attributed.string {
      try seek(oldPosition)
    } else {
      message = "Script changed; position reset"
    }
    onChange?()
  }
  func noteFrame(target: Double, end: Double?) throws {
    guard state == .running else { return }
    guard target.isFinite, target >= 0 else { throw TimelineError.invalidTime }
    guard target >= timeline.anchorTime else { return }
    if StallPolicy.shouldPause(previous: lastPresentedTarget, target: target) {
      try pauseSafely("Paused after display stall")
      return
    }
    if let lastPresentedTarget, target < lastPresentedTarget { return }
    lastPresentedTarget = target
    if let end, try timeline.position(at: target) >= end {
      try timeline.seek(to: end, at: target)
      try timeline.pause(at: target)
      state = .paused
      message = "End of script"
      onChange?()
    }
  }
  func position(at target: Double) throws -> Double {
    try timeline.position(at: max(target, timeline.anchorTime))
  }
}
@MainActor final class PresentationCoordinator {
  static let shared = PresentationCoordinator()
  weak var owner: OperatorWindowController?
  func claim(_ controller: OperatorWindowController) throws {
    if let owner, owner !== controller {
      try owner.session.pauseSafely(
        "Another document requested presentation. Stop this take first.")
      throw NSError(
        domain: "CueFlow", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "A take is active in another document. Stop that take before presenting this one."
        ])
    }
    owner = controller
  }
  func release(_ controller: OperatorWindowController) { if owner === controller { owner = nil } }
}
