import AppKit
import CueFlowCore
import QuartzCore

struct ScriptSnapshot {
  let id: UUID, documentID: UUID
  let revision: Int
  let attributed: NSAttributedString
}
struct VoiceStartIntent: Equatable {
  let generation: UInt64
  let snapshotID: UUID
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
  /// A start deferred until measurement completes: a running surface's resume or
  /// the operator's Play. Any later pause transition withdraws it.
  enum DeferredStart { case resume, play }
  var deferredStart: DeferredStart?
  var countdownSeconds = 0
  private(set) var countdownEnd: Double?
  private(set) var countdownDigit: Int?
  private(set) var elapsed = ElapsedClock()
  private(set) var timedDuration: Double?
  private(set) var voiceSessionActive = false
  private(set) var voiceSuspended = false
  private(set) var voiceEpoch: UInt64 = 0
  private(set) var voiceStartGeneration: UInt64 = 0
  var onVoicePrioritySuspended: ((String, UInt64) -> Void)?
  var onVoiceStartIntentInvalidated: ((String, UInt64) -> Void)?
  var onVoiceEnded: (() -> Void)?
  private var timedElapsedBase = 0.0
  private var scrubGate = ScrubGate()
  var canStartVoice: Bool { snapshot != nil && state != .idle && timeline.direction == .forward }
  var effectiveTime: Double {
    StallPolicy.effectiveTime(
      now: max(clock(), timeline.anchorTime), presented: lastPresentedTarget)
  }
  var elapsedSeconds: Double { elapsed.value(at: effectiveTime) }
  var effectiveLPM: Double { timeline.velocity * 60 / lineAdvance }
  func beginVoiceStartIntent() -> VoiceStartIntent? {
    guard let snapshot, state != .idle else { return nil }
    invalidateVoiceStartIntent("A newer Follow Voice start replaced this request")
    return VoiceStartIntent(generation: voiceStartGeneration, snapshotID: snapshot.id)
  }
  func isCurrentVoiceStartIntent(_ intent: VoiceStartIntent) -> Bool {
    intent.generation == voiceStartGeneration && snapshot?.id == intent.snapshotID
      && state != .idle
  }
  func invalidateVoiceStartIntent(_ reason: String) {
    voiceStartGeneration &+= 1
    onVoiceStartIntentInvalidated?(reason, voiceStartGeneration)
  }
  var remainingSeconds: Double? {
    guard !voiceSessionActive else { return nil }
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
    suspendVoiceForManualCommand("Play or Pause")
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
    scrubGate.play()
    state = .running
    countdownEnd = nil
    countdownDigit = nil
    message = "Playing"
  }
  func pause() throws {
    suspendVoiceForManualCommand("Pause")
    deferredStart = nil
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
    suspendVoiceForManualCommand(reason)
    deferredStart = nil
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
    invalidateVoiceStartIntent("Stop Take")
    if voiceSessionActive {
      voiceEpoch &+= 1
      voiceSessionActive = false
      voiceSuspended = false
      onVoiceEnded?()
    }
    deferredStart = nil
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
    suspendVoiceForManualCommand("Pace change")
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
    suspendVoiceForManualCommand("Manual navigation")
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
    suspendVoiceForManualCommand("Restart")
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
    suspendVoiceForManualCommand("Direction change")
    if state == .countingDown { try pause() }
    try timeline.setDirection(
      timeline.direction == .forward ? .reverse : .forward, at: effectiveTime)
    timedDuration = nil
    message = "Direction changed — Timed Scrolling off"
    onChange?()
  }
  func step(forward: Bool) throws {
    suspendVoiceForManualCommand("Paragraph step")
    if state == .countingDown { try pause() }
    try seek(
      ParagraphIndex.target(
        position: try position(at: effectiveTime), starts: paragraphPositions, forward: forward,
        lineAdvance: lineAdvance, end: timeline.upperBound ?? paragraphPositions.last ?? 0))
  }
  func scrub(delta: Double, momentum: Bool) throws {
    suspendVoiceForManualCommand("Scrub")
    guard scrubGate.accepts(momentum: momentum) else { return }
    try pause()
    try seek(timeline.anchorPosition + delta)
  }
  func enableTimed(seconds: Double) throws {
    suspendVoiceForManualCommand("Timed Scrolling")
    if voiceSessionActive { endVoice() }
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
    invalidateVoiceStartIntent("Load Latest")
    endVoice()
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
    deferredStart = nil
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
  func beginVoice(epoch: UInt64) throws {
    guard snapshot != nil, state != .idle else {
      throw CocoaError(.validationMissingMandatoryProperty)
    }
    guard timeline.direction == .forward else {
      throw NSError(
        domain: "CueGlass", code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Switch to Forward before starting Follow Voice."])
    }
    deferredStart = nil
    let time = effectiveTime
    if timedDuration != nil {
      timedDuration = nil
      message = "Timed Scrolling off — Follow Voice on"
    }
    try timeline.clearVoiceCeiling(at: time)
    try timeline.setVelocity(
      min(timeline.velocity, lineAdvance * configuredMax / 60), at: time)
    try timeline.setVoiceCeiling(try timeline.position(at: time), at: time)
    try timeline.play(at: time)
    elapsed.play(at: time)
    lastPresentedTarget = time
    scrubGate.play()
    state = .running
    voiceSessionActive = true
    voiceSuspended = false
    voiceEpoch = epoch
    countdownEnd = nil
    countdownDigit = nil
    message = "Waiting for speech"
    onChange?()
  }
  func voiceGlide(to target: Double, epoch: UInt64) throws {
    guard voiceSessionActive, !voiceSuspended, voiceEpoch == epoch,
      state == .running, timeline.direction == .forward
    else { return }
    let time = effectiveTime
    let current = try timeline.position(at: time)
    guard target.isFinite, target > current else { return }
    let maximum = max(0.1, lineAdvance * configuredMax / 60)
    try timeline.setVelocity(min(timeline.velocity, maximum), at: time)
    try timeline.setVoiceCeiling(target, at: time)
    onChange?()
  }
  func voiceJump(to target: Double, epoch: UInt64) throws {
    guard voiceSessionActive, !voiceSuspended, voiceEpoch == epoch,
      state == .running, timeline.direction == .forward,
      target.isFinite, target >= 0
    else { return }
    let time = effectiveTime
    try timeline.seek(to: target, at: time)
    try timeline.setVoiceCeiling(target, at: time)
    lastPresentedTarget = time
    onChange?()
  }
  func voiceHold(_ reason: String, epoch: UInt64) throws {
    guard voiceSessionActive, !voiceSuspended, voiceEpoch == epoch, state == .running else {
      return
    }
    let time = effectiveTime
    try timeline.setVoiceCeiling(try timeline.position(at: time), at: time)
    message = reason
    onChange?()
  }
  func suspendVoice(_ reason: String, epoch: UInt64) {
    guard voiceSessionActive else { return }
    voiceEpoch = epoch
    suspendVoicePosition()
    message = "Following paused — \(reason)"
    onChange?()
  }
  func resumeVoice(epoch: UInt64) throws {
    guard voiceSessionActive, voiceSuspended, snapshot != nil else { return }
    guard timeline.direction == .forward else {
      throw NSError(
        domain: "CueGlass", code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Switch to Forward before resuming Follow Voice."])
    }
    voiceEpoch = epoch
    let time = effectiveTime
    try timeline.setVoiceCeiling(try timeline.position(at: time), at: time)
    try timeline.play(at: time)
    elapsed.play(at: time)
    lastPresentedTarget = time
    state = .running
    voiceSuspended = false
    message = "Waiting for speech"
    onChange?()
  }
  func endVoice() {
    guard voiceSessionActive else { return }
    voiceEpoch &+= 1
    if !voiceSuspended && (state == .running || state == .countingDown) {
      let time = effectiveTime
      try? timeline.clearVoiceCeiling(at: time)
      try? timeline.pause(at: time)
      elapsed.pause(at: time)
      state = .paused
    } else if voiceSuspended {
      try? timeline.clearVoiceCeiling(at: effectiveTime)
    }
    voiceSessionActive = false
    voiceSuspended = false
    countdownEnd = nil
    countdownDigit = nil
    message = "Follow Voice stopped"
    onVoiceEnded?()
    onChange?()
  }
  private func suspendVoiceForManualCommand(_ reason: String) {
    invalidateVoiceStartIntent(reason)
    guard voiceSessionActive, !voiceSuspended else { return }
    voiceEpoch &+= 1
    suspendVoicePosition()
    message = "Following paused — \(reason)"
    onVoicePrioritySuspended?(reason, voiceEpoch)
  }
  func suspendVoiceForManualControl(_ reason: String) {
    suspendVoiceForManualCommand(reason)
  }
  private func suspendVoicePosition() {
    let time = effectiveTime
    try? timeline.clearVoiceCeiling(at: time)
    voiceSuspended = true
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
      if voiceSessionActive { endVoice() }
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
