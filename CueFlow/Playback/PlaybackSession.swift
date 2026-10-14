import AppKit
import CueFlowCore
import QuartzCore

struct ScriptSnapshot {
  let id: UUID, documentID: UUID
  let revision: Int
  let attributed: NSAttributedString
}
@MainActor final class PlaybackSession {
  enum State { case idle, paused, running, countingDown }
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
  var preferredLPM = 30.0, configuredMax = 240.0
  var lineAdvance = 80.0
  var paragraphPositions: [Double] = []
  var words = 0, lines = 0
  var measuring = false
  var countdownSeconds = 0
  private(set) var countdownEnd: Double?
  private(set) var countdownDigit: Int?
  private(set) var elapsed = ElapsedClock()
  private(set) var timedDuration: Double?
  private var timedElapsedBase = 0.0
  private var scrubGate = ScrubGate()
  var effectiveTime: Double {
    StallPolicy.effectiveTime(
      now: max(clock(), timeline.anchorTime), presented: lastPresentedTarget)
  }
  var elapsedSeconds: Double { elapsed.value(at: effectiveTime) }
  var effectiveLPM: Double { timeline.velocity * 60 / lineAdvance }
  var remainingSeconds: Double? {
    guard let upper = timeline.upperBound else { return nil }
    let p =
      timeline.anchorPosition
      + (state == .running
        ? timeline.direction.sign * timeline.velocity * max(0, effectiveTime - timeline.anchorTime)
        : 0)
    return max(0, timeline.direction == .forward ? upper - p : p) / timeline.velocity
  }
  func prepare(_ doc: ScriptDocument) throws {
    guard state == .idle else { return }
    guard doc.cloudStatus != .notDownloaded, doc.cloudStatus != .downloading else {
      throw NSError(
        domain: "CueGlass", code: 4,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The newer script is still downloading. The current take was kept. Try Load Latest after download finishes."
        ])
    }
    let nextStyle = doc.model.readingStyle
    let advance = PresentationFont.lineAdvance(nextStyle)
    let pace = try SpeedModel(
      lpm: doc.model.preferredSpeedLinesPerMinute, lineAdvance: advance,
      configuredMax: configuredMax)
    var next = PlaybackTimeline()
    try next.setVelocity(pace.pointsPerSecond, at: clock())
    snapshot = ScriptSnapshot(
      id: UUID(), documentID: doc.model.documentID, revision: doc.revision,
      attributed: doc.source.copy() as! NSAttributedString)
    timeline = next
    style = nextStyle
    preferredLPM = doc.model.preferredSpeedLinesPerMinute
    lineAdvance = advance
    state = .paused
    pendingRevision = false
    message = "Paused"
  }
  func toggle(_ doc: ScriptDocument) throws {
    try prepare(doc)
    if state == .running || state == .countingDown {
      try pause()
      return
    }
    if try timeline.boundReached(at: effectiveTime) {
      message =
        timeline.direction == .forward
        ? "End of script — Restart to read again" : "Start of script — switch direction"
      onChange?()
      return
    }
    if timedDuration != nil { try resolveTimed() }
    if countdownSeconds > 0 {
      countdownEnd = effectiveTime + Double(countdownSeconds)
      countdownDigit = countdownSeconds
      state = .countingDown
      message = "Starting"
    } else {
      try start(at: effectiveTime)
    }
    onChange?()
  }
  private func start(at time: Double) throws {
    try timeline.play(at: time)
    elapsed.play(at: time)
    lastPresentedTarget = time
    state = .running
    countdownEnd = nil
    countdownDigit = nil
    scrubGate.play()
    message = "Playing"
  }
  func pause() throws {
    guard state != .idle else { return }
    let time = effectiveTime
    try timeline.pause(at: time)
    elapsed.pause(at: time)
    state = .paused
    countdownEnd = nil
    countdownDigit = nil
    message = "Paused"
    onChange?()
  }
  func pauseSafely(_ reason: String) throws {
    guard state != .idle else { return }
    let time = max(timeline.anchorTime, lastPresentedTarget ?? effectiveTime)
    try timeline.pause(at: time)
    elapsed.pause(at: time)
    state = .paused
    countdownEnd = nil
    countdownDigit = nil
    message = reason
    onChange?()
  }
  func stop() {
    timeline = PlaybackTimeline()
    snapshot = nil
    state = .idle
    lastPresentedTarget = nil
    pendingRevision = false
    countdownEnd = nil
    countdownDigit = nil
    elapsed = ElapsedClock()
    timedDuration = nil
    message = "Stopped — editing enabled"
    onChange?()
  }
  func speed(_ lpm: Double) throws {
    let pace = try SpeedModel(lpm: lpm, lineAdvance: lineAdvance, configuredMax: configuredMax)
    try timeline.setVelocity(pace.pointsPerSecond, at: effectiveTime)
    preferredLPM = pace.nominalLPM
    if timedDuration != nil {
      timedDuration = nil
      message = "Timed Scrolling disabled by manual pace change"
    }
    onChange?()
  }
  func updateLayout(
    end: Double?, paragraphs: [Double], wordCount: Int, lineCount: Int, position: Double? = nil
  ) throws {
    lineAdvance = PresentationFont.lineAdvance(style)
    let pace = try SpeedModel(
      lpm: preferredLPM, lineAdvance: lineAdvance, configuredMax: configuredMax)
    try timeline.setVelocity(pace.pointsPerSecond, at: effectiveTime)
    try timeline.setUpperBound(end, at: effectiveTime)
    if let position {
      try timeline.seek(to: position, at: effectiveTime)
      lastPresentedTarget = nil
    }
    paragraphPositions = paragraphs
    words = wordCount
    lines = lineCount
    if timedDuration != nil {
      do { try resolveTimed() } catch let error as NSError {
        timedDuration = nil
        message = error.localizedDescription
      }
    }
    onChange?()
  }
  func seek(_ position: Double) throws {
    if state == .countingDown { try pause() }
    try timeline.seek(to: position, at: effectiveTime)
    lastPresentedTarget = nil
    if timedDuration != nil {
      do { try resolveTimed() } catch let error as NSError {
        timedDuration = nil
        message = error.localizedDescription
      }
    }
    onChange?()
  }
  func restart() throws {
    let duration = timedDuration
    try pause()
    elapsed = ElapsedClock()
    timedElapsedBase = 0
    try timeline.setDirection(.forward, at: effectiveTime)
    try seek(0)
    if duration == nil || timedDuration != nil { message = "Restarted — paused" }
    onChange?()
  }
  func reverse() throws {
    if state == .countingDown { try pause() }
    try timeline.setDirection(
      timeline.direction == .forward ? .reverse : .forward, at: effectiveTime)
    timedDuration = nil
    message = "Direction changed — Timed Scrolling off"
    onChange?()
  }
  func step(forward: Bool) throws {
    if state == .countingDown { try pause() }
    try seek(
      ParagraphIndex.target(
        position: try position(at: effectiveTime), starts: paragraphPositions, forward: forward,
        lineAdvance: lineAdvance, end: timeline.upperBound ?? paragraphPositions.last ?? 0))
  }
  func scrub(delta: Double, momentum: Bool) throws {
    guard scrubGate.accepts(momentum: momentum) else { return }
    try pause()
    try seek(timeline.anchorPosition + delta)
  }
  func enableTimed(seconds: Double) throws {
    guard timeline.direction == .forward else {
      throw NSError(
        domain: "CueGlass", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Switch to Forward before enabling Timed Scrolling."])
    }
    let lpm = try TimedScrollSolver.solve(
      position: try position(at: effectiveTime), end: timeline.upperBound, seconds: seconds,
      lineAdvance: lineAdvance, maximum: configuredMax)
    try timeline.setVelocity(
      SpeedModel(lpm: lpm, lineAdvance: lineAdvance, configuredMax: configuredMax).pointsPerSecond,
      at: effectiveTime)
    preferredLPM = lpm
    timedDuration = seconds
    timedElapsedBase = elapsedSeconds
    message = "Timed Scrolling enabled"
    onChange?()
  }
  private func resolveTimed() throws {
    guard let total = timedDuration else { return }
    let remaining = total - (elapsedSeconds - timedElapsedBase)
    let lpm = try TimedScrollSolver.solve(
      position: try position(at: effectiveTime), end: timeline.upperBound, seconds: remaining,
      lineAdvance: lineAdvance, maximum: configuredMax)
    try timeline.setVelocity(
      SpeedModel(lpm: lpm, lineAdvance: lineAdvance, configuredMax: configuredMax).pointsPerSecond,
      at: effectiveTime)
    preferredLPM = lpm
  }
  func changed(_ doc: ScriptDocument) {
    if let snapshot, snapshot.revision != doc.revision {
      pendingRevision = true
      message = "Newer version available — pause and Load Latest"
      onChange?()
    }
  }
  func loadLatest(_ doc: ScriptDocument) throws {
    guard state != .running, state != .countingDown else {
      throw CocoaError(.validationMissingMandatoryProperty)
    }
    // Prepare and validate every replacement value before touching the existing take (T3).
    let candidate = PlaybackSession()
    candidate.clock = clock
    candidate.configuredMax = configuredMax
    try candidate.prepare(doc)
    let same = snapshot?.attributed.string == candidate.snapshot?.attributed.string
    if same {
      try candidate.timeline.seek(to: try position(at: effectiveTime), at: candidate.effectiveTime)
    }
    snapshot = candidate.snapshot
    timeline = candidate.timeline
    state = .paused
    style = candidate.style
    lineAdvance = candidate.lineAdvance
    preferredLPM = candidate.preferredLPM
    pendingRevision = false
    lastPresentedTarget = nil
    countdownEnd = nil
    countdownDigit = nil
    timedDuration = nil
    elapsed = ElapsedClock()
    message = same ? "Latest revision loaded — paused" : "Script changed; position reset"
    onChange?()
  }
  func noteFrame(target: Double, end: Double?) throws {
    guard target.isFinite, target >= 0 else { throw TimelineError.invalidTime }
    if state == .countingDown, let deadline = countdownEnd {
      if target >= deadline {
        try start(at: max(deadline, timeline.anchorTime))
        onChange?()
      } else {
        let digit = Int(ceil(deadline - target))
        if digit != countdownDigit {
          countdownDigit = digit
          onChange?()
        }
        return
      }
    }
    guard state == .running, target >= timeline.anchorTime else { return }
    if StallPolicy.shouldPause(previous: lastPresentedTarget, target: target) {
      try pauseSafely("Paused after display stall")
      return
    }
    if let previous = lastPresentedTarget, target < previous { return }
    lastPresentedTarget = target
    if timeline.upperBound == nil, let end { try timeline.setUpperBound(end, at: target) }
    if try timeline.boundReached(at: target) {
      try timeline.pause(at: target)
      elapsed.pause(at: target)
      state = .paused
      message =
        timeline.direction == .forward
        ? "End of script — Restart to read again" : "Start of script — held"
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
        domain: "CueGlass", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Stop the active take in the other document before presenting this one."
        ])
    }
    owner = controller
  }
  func release(_ controller: OperatorWindowController) { if owner === controller { owner = nil } }
}
