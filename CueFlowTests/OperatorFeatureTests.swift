import AppKit
import CueFlowCore
import QuartzCore
import Testing

@testable import CueFlow

@MainActor private final class CameraDockVoiceCaptureProbe: VoiceCaptureSource {
  var startCount = 0
  var stopCount = 0
  private var continuation: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?

  func supportedLocales() async -> [VoiceLocaleOption] {
    [VoiceLocaleOption(identifier: "en-US", displayName: "English (US)")]
  }
  func readiness(localeIdentifier: String) async -> VoiceAssetReadiness { .ready }
  func install(localeIdentifier: String, reportProgress: @escaping (Double) -> Void) async throws {}
  func cancelModelInstallation() {}
  func start(localeIdentifier: String) async throws -> AsyncThrowingStream<
    TranscriptEvent, any Error
  > {
    startCount += 1
    let pair = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }
  func send(_ event: TranscriptEvent) { continuation?.yield(event) }
  func stop() {
    stopCount += 1
    continuation?.finish()
    continuation = nil
  }
}

@MainActor private final class CameraDockMicrophoneProbe: MicrophonePermissionChecking {
  var permission: MicrophonePermissionState
  private(set) var requestCount = 0

  init(_ permission: MicrophonePermissionState) { self.permission = permission }
  func requestPermission() async -> Bool {
    requestCount += 1
    return permission == .granted
  }
}

@Suite(.serialized) @MainActor struct OperatorFeatureTests {
  init() { _ = NSApplication.shared }
  private func settle(_ controller: OperatorWindowController) async {
    for _ in 0..<2000 {
      if !controller.session.measuring { return }
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    Issue.record("Measurement did not settle in 2000 main queue turns")
  }
  private func mainTurn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
  private func presentationWindowIDs() -> Set<ObjectIdentifier> {
    Set(NSApp.windows.compactMap { $0 as? PresentationPanel }.map { ObjectIdentifier($0) })
  }
  private func awaitVoiceUpdate(
    _ coordinator: VoiceFollowCoordinator, matching condition: @escaping () -> Bool,
    label: String, timeoutTurns: Int = 2_000, perform action: @escaping () -> Void
  ) async -> Bool {
    if condition() { return true }
    let matched = await withCheckedContinuation {
      (continuation: CheckedContinuation<Bool, Never>) in
      Task { @MainActor in
        var completed = false
        let previous = coordinator.onChange
        let finish: @MainActor () -> Void = {
          guard !completed else { return }
          completed = true
          coordinator.onChange = previous
          continuation.resume(returning: condition())
        }
        coordinator.onChange = {
          previous?()
          guard !completed, condition() else { return }
          finish()
        }
        action()
        Task { @MainActor in
          for _ in 0..<timeoutTurns {
            if completed { return }
            await mainTurn()
          }
          finish()
        }
      }
    }
    if !matched {
      Issue.record("Timed out waiting for Follow Voice \(label); last state: \(coordinator.state)")
    }
    return matched
  }
  private func prepared(
    _ paragraphs: Int = 200, paragraphText: String? = nil
  ) async throws -> OperatorWindowController {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<paragraphs).map { index in
        paragraphText.map { "\($0) \(index)" }
          ?? "Paragraph \(index) alpha beta gamma delta epsilon"
      }.joined(separator: "\n"))
    let controller = OperatorWindowController(document: doc)
    controller.session.clock = { 0 }
    controller.state.countdown = 5
    try controller.session.prepare(doc)
    controller.render()
    #expect(controller.session.measuring == (paragraphs > 64))
    await settle(controller)
    #expect((controller.authoritative.measurementChunkCount > 1) == (paragraphs > 64))
    return controller
  }
  private func dockParameters(
    for screen: NSScreen, safeTop: Double = 0, topInset: Double = 0,
    left: CameraDockRect? = nil, right: CameraDockRect? = nil
  ) -> CameraDockScreenParameters {
    let screenFrame = screen.frame
    let visible = screen.visibleFrame
    return CameraDockScreenParameters(
      screenFrame: CameraDockRect(
        x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width,
        height: screenFrame.height),
      visibleFrame: CameraDockRect(
        x: visible.minX, y: visible.minY, width: visible.width,
        height: max(0, visible.height - topInset)),
      safeTop: safeTop, auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right)
  }
  private func syntheticDisplay(
    screen: NSScreen, id: CGDirectDisplayID, uuid: String, isBuiltIn: Bool = false,
    isMirrored: Bool = false, parameters: CameraDockScreenParameters? = nil
  ) -> DisplayDescriptor {
    DisplayDescriptor(
      screen: screen, preference: DisplayPreference(uuid: uuid, name: uuid), id: id,
      isBuiltIn: isBuiltIn, isMirrored: isMirrored, cameraDockParameters: parameters)
  }
  private func enterExitEvent(_ type: NSEvent.EventType) throws -> NSEvent {
    try #require(
      NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
  }
  private func elementCount(_ path: CGPath) -> Int {
    var count = 0
    path.applyWithBlock { _ in count += 1 }
    return count
  }
  /// Instrument, not an assertion: with `CUEFLOW_DOCK_SILHOUETTE_DIR` set, writes one PNG
  /// per morph state so a reviewer can look at the attached silhouette without a notched Mac.
  private func writeCameraDockSilhouettes(layout: CameraDockLayout, bounds: CGRect) throws {
    guard let directory = ProcessInfo.processInfo.environment["CUEFLOW_DOCK_SILHOUETTE_DIR"]
    else { return }
    let origin = CGPoint(x: layout.placement.frame.minX, y: layout.placement.frame.minY)
    let states: [(String, Double, Bool)] = [
      ("1-parked", 0, true), ("2-midway", 0.5, true), ("3-open-ready", 1, true),
      ("4-open-playing", 1, false),
    ]
    let scale: CGFloat = 2
    let margin: CGFloat = 40
    for (name, progress, controls) in states {
      let metrics = try #require(
        CameraDockGeometry.morphMetrics(for: layout, progress: progress, controlsVisible: controls))
      let path = FloatingRoot.attachedPath(metrics, in: bounds, frameOrigin: origin)
      let size = CGSize(width: bounds.width + margin * 2, height: bounds.height)
      let context = try #require(
        CGContext(
          data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.scaleBy(x: scale, y: scale)
      context.setFillColor(CGColor(red: 0.42, green: 0.62, blue: 0.66, alpha: 1))
      context.fill(CGRect(origin: .zero, size: size))
      // Menu-bar band and the pixel-free housing, for context.
      let band = CGRect(
        x: 0, y: size.height - layout.contentTopInset, width: size.width,
        height: layout.contentTopInset)
      context.setFillColor(CGColor(red: 0.3, green: 0.47, blue: 0.5, alpha: 1))
      context.fill(band)
      if let housing = layout.cameraHousing {
        context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1))
        context.fill(
          CGRect(
            x: margin + housing.minX - origin.x, y: band.minY, width: housing.width,
            height: band.height))
      }
      context.translateBy(x: margin, y: 0)
      context.addPath(path)
      context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
      context.fillPath()
      let image = try #require(context.makeImage())
      let representation = NSBitmapImageRep(cgImage: image)
      let data = try #require(representation.representation(using: .png, properties: [:]))
      let url = URL(fileURLWithPath: directory).appendingPathComponent(
        "camera-dock-\(name).png")
      try data.write(to: url)
    }
  }
  @Test func finalFragmentGeometryKeepsAnchorAndTimedDeadline() async throws {
    for count in [20, 64, 65, 200] {
      for paragraph in [count - 2, count - 1] {
        let c = try await prepared(count)
        defer { c.close() }
        var time = 0.0
        c.session.clock = { time }
        c.session.countdownSeconds = 0
        // Consume playing time before selecting a feasible plan near the end.
        try c.session.toggle(c.script)
        for frame in 1...40 {
          time = Double(frame) / 4
          try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
        }
        try c.session.pause()
        c.seek(c.session.paragraphPositions[paragraph])
        let anchor = try #require(c.authoritative.captureAnchor())
        try c.session.enableTimed(seconds: 60)
        for resize in [false, true] {
          if resize {
            // Use the same pause/anchor/render path as a presentation resize.
            c.showFloating()
            c.floating?.reflection.viewport.driver?.stop()
            c.floating?.reflection.viewport.driver = nil
            await settle(c)
            let window = try #require(c.floating?.window)
            window.setContentSize(CGSize(width: 600, height: 350))
            c.floatingResized()
          } else {
            var style = c.state.style
            style.fontSize = 120
            c.changeStyle(style)
          }
          await settle(c)
          // Record all product values before the observational TextKit query.
          let bound = try #require(c.session.timeline.upperBound)
          let cached = try #require(c.authoritative.endPosition)
          let position = c.session.timeline.anchorPosition
          let remaining = try #require(c.session.remainingSeconds)
          let velocity = c.session.timeline.velocity
          let manager = try #require(c.authoritative.text.textLayoutManager)
          let content = try #require(manager.textContentManager)
          let location = try #require(
            content.location(
              content.documentRange.location,
              offsetBy: c.authoritative.text.string.utf16.count - 1))
          let final = try #require(manager.textLayoutFragment(for: location))
          #expect(final.state == .layoutAvailable)
          let actualEnd = final.layoutFragmentFrame.maxY
          #expect(abs(bound - actualEnd) < 0.00001)
          #expect(abs(cached - actualEnd) < 0.00001)
          #expect(abs((actualEnd - position) / velocity - remaining) < 0.00001)
          #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
          #expect(abs(position - (c.authoritative.restore(anchor) ?? -1)) < 1)
          #expect(c.session.timedDuration == 60)
          #expect(abs(remaining - 60) < 0.00001)
          #expect(c.session.elapsedSeconds == 10)
        }
        c.restart()
        if c.session.timedDuration != nil {
          #expect(c.session.timedDuration == 60)
          #expect(abs((c.session.remainingSeconds ?? -1) - 60) < 0.00001)
        } else {
          #expect(c.session.message.contains("maximum"))
        }
        #expect(c.session.elapsedSeconds == 0)
        #expect(c.session.timeline.anchorPosition == 0)
        #expect(c.session.state == .paused)
      }
    }
  }
  @Test func asynchronousAnchorMatrix() async throws {
    // A1–A8: growth early/late, synchronous control, shrink, margin, column, line and supersession.
    for scenario in 1...8 {
      let short = scenario == 3
      let c = try await prepared(short ? 20 : 200)
      defer { c.close() }
      if scenario == 4 {
        var style = c.state.style
        style.fontSize = 120
        c.changeStyle(style)
        #expect(c.session.measuring)
        await settle(c)
      }
      c.seek(c.session.paragraphPositions[short ? 18 : (scenario == 2 ? 20 : 180)])
      let anchor = try #require(c.authoritative.captureAnchor())
      let source = c.script.source.copy() as! NSAttributedString
      let snapshot = c.session.snapshot?.id
      var style = c.state.style
      switch scenario {
      case 4: style.fontSize = 64
      case 5: style.sideMarginFraction = 0.25
      case 6: style.columnWidthFraction = 0.5
      case 7: style.lineHeightMultiplier = 2
      default: style.fontSize = 120
      }
      c.changeStyle(style)
      #expect(c.session.measuring == !short)
      if scenario == 8 {
        style.fontSize = 100
        c.changeStyle(style)
        #expect(c.session.measuring)
      }
      await settle(c)
      let expected = try #require(c.authoritative.restore(anchor))
      #expect(abs(c.session.timeline.anchorPosition - expected) < 1)
      #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
      #expect(c.session.state == .paused)
      #expect(c.session.preferredLPM == 30)
      #expect(c.session.snapshot?.id == snapshot)
      #expect(c.script.source == source)
    }
  }
  @Test func asynchronousResumeAndStartMatrix() async throws {
    for scenario in 1...6 {
      let c = try await prepared(scenario == 2 ? 20 : 200)
      defer { c.close() }
      if scenario <= 4 {
        c.session.countdownSeconds = 0
        try c.session.toggle(c.script)
        try c.session.pause()
        c.render()
        #expect(c.session.measuring == (scenario != 2))
        c.resumeAfterMeasurement()
      } else {
        var style = c.state.style
        style.fontSize = 120
        c.changeStyle(style)
        #expect(c.session.measuring)
      }
      if scenario == 3 { c.toggle() }
      if scenario == 4 {
        var style = c.state.style
        style.fontSize = 120
        c.changeStyle(style)
      }
      if scenario == 5 { c.toggle() }
      if scenario == 6 {
        c.resumeAfterMeasurement()
        c.stop()
        // Drain the already queued obsolete completion as well as the current generation.
        await withCheckedContinuation { continuation in
          DispatchQueue.main.async { continuation.resume() }
        }
      }
      await settle(c)
      let expected: PlaybackSession.State =
        scenario <= 2
        ? .running : (scenario == 5 ? .countingDown : (scenario == 6 ? .idle : .paused))
      #expect(c.session.state == expected)
      #expect(c.session.countdownDigit == (scenario == 5 ? 5 : nil))
      #expect(!c.session.measuring)
      #expect(!c.pendingPlay)
      #expect(!c.pendingResume)
      if scenario == 6 {
        #expect(c.pendingAnchor == nil)
        #expect(!c.readout.status.contains("Measuring"))
      }
    }
  }
  @Test func pendingUserStartCanBeCancelledOrSuperseded() async throws {
    for supersede in [false, true] {
      let c = try await prepared()
      defer { c.close() }
      var style = c.state.style
      style.fontSize = 120
      c.changeStyle(style)
      #expect(c.session.measuring)
      c.toggle()
      if supersede {
        style.fontSize = 100
        c.changeStyle(style)
      } else {
        c.toggle()
      }
      await settle(c)
      #expect(c.session.state == .paused)
      #expect(c.session.countdownDigit == nil)
    }
  }
  @Test func navigationWinsDuringMeasurement() async throws {
    for scenario in 0..<6 {
      let c = try await prepared()
      defer { c.close() }
      c.seek(c.session.paragraphPositions[180])
      var style = c.state.style
      style.fontSize = 120
      c.changeStyle(style)
      #expect(c.session.measuring)
      switch scenario {
      case 0: c.seek(100)
      case 1: c.execute(.nextParagraph)
      case 2: c.execute(.previousParagraph)
      case 3: c.restart()
      case 4: c.execute(.reverse)
      default:
        c.scrub(delta: -100, momentum: false)
      }
      #expect(c.pendingAnchor == nil)
      let intended = c.session.timeline.anchorPosition
      await settle(c)
      #expect(c.session.timeline.anchorPosition == intended)
      #expect(c.session.state == .paused)
      if scenario == 4 { #expect(c.session.timeline.direction == .reverse) }
    }
  }
  @Test func latestRevisionRestoresOnlyItsOwnAnchor() async throws {
    for changedText in [false, true] {
      let c = try await prepared()
      defer { c.close() }
      c.seek(c.session.paragraphPositions[180])
      var style = c.state.style
      style.fontSize = 120
      c.changeStyle(style)
      #expect(c.session.measuring)
      c.seek(1000)
      let current = try #require(c.authoritative.captureAnchor())
      let oldID = c.session.snapshot?.id
      if changedText {
        c.script.replaceSource(NSAttributedString(string: "Replacement\n" + c.script.source.string))
      }
      c.loadLatest()
      #expect(c.session.measuring)
      await settle(c)
      #expect(c.session.snapshot?.id != oldID)
      #expect(c.session.snapshot?.attributed == c.script.source)
      #expect(c.session.state == .paused)
      if changedText {
        #expect(c.session.timeline.anchorPosition == 0)
      } else {
        #expect(c.authoritative.captureAnchor()?.utf16Offset == current.utf16Offset)
      }
    }
  }
  @Test func feasibleTimedRelayoutKeepsDeadline() async throws {
    let c = try await prepared()
    defer { c.close() }
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[180])
    let anchor = try #require(c.authoritative.captureAnchor())
    try c.session.enableTimed(seconds: 100)
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...40 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    try c.session.pause()
    let remaining = try #require(c.session.remainingSeconds)
    let readingAnchor = try #require(c.authoritative.captureAnchor())
    #expect(readingAnchor.utf16Offset >= anchor.utf16Offset)
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.timedDuration != nil)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == readingAnchor.utf16Offset)
    #expect(abs((c.session.remainingSeconds ?? -1) - remaining) < 0.00001)
    #expect(c.session.elapsedSeconds == 10)
    #expect(c.session.state == .paused)
    #expect(c.session.effectiveLPM >= 2 && c.session.effectiveLPM <= 240)
  }
  @Test func restartResetsPendingTimedDeadline() async throws {
    let c = try await prepared()
    defer { c.close() }
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[100])
    try c.session.enableTimed(seconds: 600)
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...40 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    #expect(c.session.measuring)
    c.restart()
    await settle(c)
    #expect(c.session.timeline.anchorPosition == 0)
    #expect(c.session.elapsedSeconds == 0)
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 600) < 0.00001)
    #expect(c.session.state == .paused)
  }
  @Test func completedRelayoutKeepsBudgetAndRestart() async throws {
    let c = try await prepared()
    defer { c.close() }
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[100])
    try c.session.enableTimed(seconds: 600)
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...40 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.timedDuration == 600)
    #expect(c.session.elapsedSeconds == 10)
    #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
    c.restart()
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 600) < 0.00001)
    #expect(c.session.elapsedSeconds == 0)
    #expect(c.session.state == .paused)
  }
  @Test func lateEnabledPlanKeepsItsElapsedBaseThroughRestart() async throws {
    for inFlight in [false, true] {
      let c = try await prepared()
      defer { c.close() }
      var time = 0.0
      c.session.clock = { time }
      c.seek(c.session.paragraphPositions[180])
      c.session.countdownSeconds = 0
      try c.session.toggle(c.script)
      for frame in 1...20 {
        time = Double(frame) / 4
        try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
      }
      try c.session.enableTimed(seconds: 600)
      for frame in 21...60 {
        time = Double(frame) / 4
        try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
      }
      var style = c.state.style
      style.fontSize = 120
      c.changeStyle(style)
      #expect(c.session.measuring)
      if !inFlight {
        await settle(c)
        #expect(c.session.elapsedSeconds == 15)
        #expect(c.session.timedDuration == 600)
        #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
      }
      c.restart()
      await settle(c)
      #expect(c.session.timedDuration == 600)
      #expect(abs((c.session.remainingSeconds ?? -1) - 600) < 0.00001)
      #expect(c.session.timeline.anchorPosition == 0)
      #expect(c.session.elapsedSeconds == 0)
      #expect(c.session.state == .paused)
    }
  }
  @Test func timedNavigationWinsDuringMeasurementAndRestart() async throws {
    let c = try await prepared()
    defer { c.close() }
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[100])
    try c.session.enableTimed(seconds: 600)
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...40 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    #expect(c.session.measuring)
    c.seek(1000)
    await settle(c)
    #expect(c.session.timeline.anchorPosition == 1000)
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
    c.restart()
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 600) < 0.00001)
    #expect(c.session.timeline.anchorPosition == 0)
  }
  @Test func timedRunningSurfacesKeepDeadlineAndRestart() async throws {
    for fullscreen in [false, true] {
      let c = try await prepared()
      defer { c.close() }
      var time = 0.0
      c.session.clock = { time }
      c.seek(c.session.paragraphPositions[100])
      try c.session.enableTimed(seconds: 600)
      c.session.countdownSeconds = 0
      try c.session.toggle(c.script)
      for frame in 1...40 {
        time = Double(frame) / 4
        try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
      }
      if fullscreen {
        let display = try #require(DisplayDescriptor.all().first)
        c.state.selectedDisplay = display.selectionKey
        c.showOutput(confirm: { _ in .alertFirstButtonReturn })
        let viewport = try #require(c.output?.reflection.viewport)
        viewport.driver?.stop()
        viewport.driver = nil
      } else {
        c.showFloating()
        let viewport = try #require(c.floating?.reflection.viewport)
        viewport.driver?.stop()
        viewport.driver = nil
      }
      #expect(c.session.measuring)
      await settle(c)
      #expect(c.session.state == .running)
      #expect(c.session.countdownDigit == nil)
      #expect(c.session.timedDuration == 600)
      #expect(c.session.elapsedSeconds == 10)
      #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
      for frame in 41...60 {
        time = Double(frame) / 4
        try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
      }
      if !fullscreen {
        let window = try #require(c.floating?.window)
        window.setContentSize(CGSize(width: 600, height: 350))
        c.floatingResized()
        #expect(c.session.measuring)
        await settle(c)
      }
      #expect(c.session.state == .running)
      #expect(c.session.countdownDigit == nil)
      #expect(c.session.elapsedSeconds == 15)
      #expect(c.session.timedDuration == 600)
      #expect(abs((c.session.remainingSeconds ?? -1) - 585) < 0.00001)
      c.restart()
      #expect(c.session.timedDuration == 600)
      #expect(abs((c.session.remainingSeconds ?? -1) - 600) < 0.00001)
      #expect(c.session.timeline.anchorPosition == 0)
      #expect(c.session.state == .paused)
    }
  }
  @Test func cameraDockPanelAndReturnToPreviewPreserveTheTake() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    let oldSize = c.session.logicalSize
    let oldSnapshot = try #require(c.session.snapshot?.id)
    c.seek(c.session.paragraphPositions[40])
    let oldAnchor = try #require(c.authoritative.captureAnchor())

    c.selectPresentationSurface("cameraDock")
    let dock = try #require(c.cameraDock)
    let panel = try #require(dock.window)
    let screen = try #require(panel.screen)
    let visible = screen.visibleFrame
    #expect(dock.isCameraDock)
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.canBecomeKey)
    #expect(!panel.isMovable)
    #expect(!panel.isMovableByWindowBackground)
    #expect(!panel.isOpaque)
    #expect(
      panel.level
        == FloatingPrompterWindowController.cameraDockWindowLevel(
          isCameraDock: true, style: dock.dockStyle))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
    #expect(panel.isVisible)
    #expect(c.state.cameraDockReady)
    #expect(!c.state.running)
    #expect(!c.pendingResume)
    #expect(CameraDockGrip(state: c.state, controller: c).statusText == "Ready · Space to play")
    #expect(NSApp.modalWindow == nil)
    #expect(panel.frame.minX >= visible.minX - 0.5)
    #expect(panel.frame.maxX <= visible.maxX + 0.5)
    #expect(panel.frame.minY >= visible.minY - 0.5)
    if dock.dockStyle == .attached {
      #expect(panel.frame.maxY <= screen.frame.maxY + 0.5)
    } else {
      #expect(panel.frame.maxY <= visible.maxY + 0.5)
    }
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    #expect(c.session.state == .paused)
    #expect(c.session.snapshot?.id == oldSnapshot)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == oldAnchor.utf16Offset)
    #expect(c.selectedPresentationSurface == "cameraDock")

    c.selectPresentationSurface("preview")
    await settle(c)
    #expect(c.cameraDock == nil)
    #expect(c.output == nil)
    #expect(c.floating == nil)
    #expect(c.selectedPresentationSurface == "preview")
    #expect(c.session.logicalSize == oldSize)
    #expect(c.session.snapshot?.id == oldSnapshot)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == oldAnchor.utf16Offset)
    #expect(c.session.state == .paused)
  }

  @Test func cameraDockCommitFromEverySurfaceStagesReadyAndRestoresPlayback() async throws {
    for source in ["preview", "floating", "output"] {
      do {
        let c = try await prepared()
        defer { c.close() }
        c.preview.reflection.viewport.driver?.stop()
        let display = try #require(DisplayDescriptor.all().first)
        c.state.selectedDisplay = display.selectionKey
        if source == "floating" {
          c.showFloating()
          c.floating?.reflection.viewport.driver?.stop()
          c.floating?.reflection.viewport.driver = nil
          await settle(c)
        } else if source == "output" {
          c.showOutput(confirm: { _ in .alertFirstButtonReturn })
          c.output?.reflection.viewport.driver?.stop()
          c.output?.reflection.viewport.driver = nil
          await settle(c)
        }

        c.seek(c.session.paragraphPositions[48])
        c.state.countdown = 0
        c.toggle()
        await settle(c)
        #expect(c.session.state == .running)
        let snapshot = try #require(c.session.snapshot?.id)
        let anchor = try #require(c.authoritative.captureAnchor())

        c.showCameraDock()
        let dock = try #require(c.cameraDock)
        let dockDriver = try #require(dock.reflection.viewport.driver)
        dock.reflection.viewport.driver?.stop()
        dock.reflection.viewport.driver = nil
        await settle(c)

        #expect(c.selectedPresentationSurface == "cameraDock")
        #expect(c.output == nil)
        #expect(c.floating === dock)
        #expect(dock.window?.isVisible == true)
        #expect(dockDriver.authoritative)
        #expect(c.preview.reflection.viewport.driver?.authoritative == false)
        #expect(c.session.state == .paused)
        #expect(!c.pendingResume)
        #expect(c.state.cameraDockReady)
        #expect(c.session.snapshot?.id == snapshot)
        #expect(dock.reflection.viewport.captureAnchor()?.utf16Offset == anchor.utf16Offset)
        #expect(c.preview.placementMapView.isHidden)
        #expect(NSApp.modalWindow == nil)

        c.toggle()
        await settle(c)
        #expect(c.session.state == .running)
        #expect(!c.state.cameraDockReady)

        c.hideOutput()
        #expect(c.pendingResume, "return did not restore the source's running intent")
        c.floating?.reflection.viewport.driver?.authoritative = false
        c.output?.reflection.viewport.driver?.authoritative = false
        await settle(c)
        #expect(c.selectedPresentationSurface == source)
        #expect(
          c.session.state == .running,
          "source = \(source), pendingResume = \(c.pendingResume), measuring = \(c.session.measuring)"
        )
      }
    }
  }

  @Test func cameraDockFirstUseCalloutIsNonmodalAndAcknowledgementDismissesForSession() async throws
  {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey

    c.showCameraDock()
    #expect(c.cameraDock != nil)
    #expect(c.state.cameraDockFirstUseCalloutVisible)
    #expect(NSApp.modalWindow == nil)
    #expect(
      OperatorWindowController.cameraDockCaptureDisclosure
        == "The prompt may appear in screen recordings and full-display shares.")
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map?.caption.contains("CAMERA DOCK") == true)

    c.acknowledgeCameraDockExplainer()
    #expect(!c.state.cameraDockFirstUseCalloutVisible)
    c.hideOutput()
    await settle(c)
    c.showCameraDock()
    #expect(c.cameraDock != nil)
    #expect(!c.state.cameraDockFirstUseCalloutVisible)
    #expect(NSApp.modalWindow == nil)
  }

  @Test func cameraDockWindowUsesAttachedAndDetachedVisualStyles() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let frame = screen.frame
    let safeTop = 32.0
    let safeEdge = frame.maxY - safeTop
    let sideWidth = (frame.width - 200) / 2
    let notchedParameters = CameraDockScreenParameters(
      screenFrame: CameraDockRect(
        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
      visibleFrame: CameraDockRect(
        x: frame.minX, y: frame.minY, width: frame.width, height: safeEdge - frame.minY),
      safeTop: safeTop,
      auxiliaryTopLeftArea: CameraDockRect(
        x: frame.minX, y: safeEdge, width: sideWidth, height: safeTop),
      auxiliaryTopRightArea: CameraDockRect(
        x: frame.minX + sideWidth + 200, y: safeEdge, width: sideWidth, height: safeTop))
    let builtIn = syntheticDisplay(
      screen: screen, id: 9001, uuid: "attached-test-display", isBuiltIn: true,
      parameters: notchedParameters)
    c.displayProvider = { [builtIn] }
    c.showCameraDock()
    let attachedDock = try #require(c.cameraDock)
    let attachedWindow = try #require(attachedDock.window)
    let attachedRoot = try #require(attachedDock.root)

    #expect(attachedDock.dockStyle == .attached)
    #expect(abs(attachedWindow.frame.maxY - frame.maxY) < 0.5)
    #expect(abs(attachedDock.dockTopInset - safeTop) < 0.5)
    #expect(
      attachedWindow.level == NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3))
    #expect(!attachedWindow.hasShadow)
    #expect(!attachedWindow.isOpaque)
    let attachedColor = try #require(attachedWindow.backgroundColor.usingColorSpace(.sRGB))
    #expect(attachedColor.alphaComponent == 0)
    #expect(attachedRoot.layer?.cornerRadius == 0)
    #expect(attachedRoot.layer?.mask is CAShapeLayer)
    #expect(attachedDock.reflection.layer?.cornerRadius == 0)
    attachedRoot.layoutSubtreeIfNeeded()
    let attachedLayout = try #require(attachedDock.dockLayout)
    let clip = attachedRoot.cameraDockContentClip
    let viewport = attachedDock.reflection.viewport
    #expect(attachedRoot.reflection.superview === clip)
    #expect(abs(attachedRoot.bounds.maxY - clip.frame.maxY - safeTop) < 0.5)
    #expect(abs(clip.frame.height - attachedLayout.visibleViewportHeight) < 0.5)
    #expect(attachedRoot.reflection.frame.minY == 0)
    #expect(abs(attachedRoot.reflection.frame.height - attachedLayout.viewportHeight) < 0.5)
    #expect(
      abs(
        attachedRoot.reflection.frame.height - clip.frame.height
          - attachedLayout.hiddenViewportTop) < 0.5)
    #expect(attachedRoot.reflection.bounds.size == attachedRoot.reflection.frame.size)
    // The operator reserves `guideFraction` of the viewport above the guide; the clip hides
    // exactly that band minus the padding, so the guide line is the first visible line.
    #expect(
      abs(viewport.topPadding - attachedLayout.viewportHeight * CameraDockGeometry.guideFraction)
        < 1e-9)
    #expect(
      abs(
        viewport.topPadding - attachedLayout.hiddenViewportTop
          - CameraDockGeometry.viewportVerticalPadding) < 1e-9)
    #expect(viewport.panelBackground.isHidden)

    // Showing the Dock reveals it: the open tray with its controls band, sprung from the chin.
    #expect(attachedRoot.cameraDockIsExpanded)
    #expect(!attachedRoot.cameraDockIsParked)
    let revealedPath = try #require(attachedRoot.cameraDockMaskPath)
    #expect(revealedPath.boundingBoxOfPath.minY == attachedRoot.bounds.minY)
    #expect(revealedPath.boundingBoxOfPath.maxY == attachedRoot.bounds.maxY)
    #expect(abs(revealedPath.boundingBoxOfPath.width - attachedRoot.bounds.width) < 0.5)
    #expect(
      revealedPath.contains(NSPoint(x: attachedRoot.bounds.midX, y: attachedRoot.bounds.maxY - 1)))
    #expect(
      !revealedPath.contains(
        NSPoint(x: attachedRoot.bounds.minX + 1, y: attachedRoot.bounds.maxY - 1)))
    #expect(attachedRoot.reflection.alphaValue == 1)
    #expect(attachedRoot.grip.alphaValue == 1)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      #expect(attachedRoot.cameraDockShapeAnimation == nil)
    } else {
      let reveal = try #require(attachedRoot.cameraDockShapeAnimation as? CASpringAnimation)
      #expect(reveal.keyPath == "path")
      #expect(reveal.duration >= CameraDockMotion.minimumShapeDuration)
      #expect(reveal.duration <= CameraDockMotion.maximumShapeDuration)
      #expect(reveal.stiffness == CameraDockMotion.springStiffness)
      #expect(reveal.damping == CameraDockMotion.springDamping)
    }
    // Both morph endpoints share one element sequence, so Core Animation can interpolate.
    let origin = CGPoint(
      x: attachedLayout.placement.frame.minX, y: attachedLayout.placement.frame.minY)
    let chinMetrics = try #require(
      CameraDockGeometry.morphMetrics(for: attachedLayout, progress: 0))
    let openMetrics = try #require(
      CameraDockGeometry.morphMetrics(for: attachedLayout, progress: 1, controlsVisible: false))
    #expect(
      elementCount(
        FloatingRoot.attachedPath(chinMetrics, in: attachedRoot.bounds, frameOrigin: origin))
        == elementCount(
          FloatingRoot.attachedPath(openMetrics, in: attachedRoot.bounds, frameOrigin: origin)))

    try writeCameraDockSilhouettes(layout: attachedLayout, bounds: attachedRoot.bounds)

    // Parked: a short chin under the housing, no text, and no hit region beside it.
    attachedRoot.setCameraDockParked(true, animated: false)
    #expect(attachedRoot.cameraDockIsParked)
    #expect(!attachedRoot.cameraDockIsExpanded)
    let chin = try #require(attachedRoot.cameraDockMaskPath).boundingBoxOfPath
    #expect(chin.maxY == attachedRoot.bounds.maxY)
    #expect(
      abs(
        chin.minY
          - (attachedRoot.bounds.maxY - safeTop - CameraDockGeometry.compactChinHeight)) < 0.5)
    #expect(abs(chin.width - (200 + CameraDockGeometry.compactChinOverhang * 2)) < 0.5)
    #expect(attachedRoot.reflection.alphaValue == 0)
    #expect(attachedRoot.cameraDockShapeAnimation == nil)
    #expect(
      attachedRoot.hitTest(
        NSPoint(x: attachedRoot.bounds.minX + 2, y: attachedRoot.bounds.maxY - 2)) == nil)
    #expect(
      attachedRoot.hitTest(NSPoint(x: attachedRoot.bounds.midX, y: attachedRoot.bounds.midY))
        == nil)
    #expect(
      attachedRoot.hitTest(NSPoint(x: attachedRoot.bounds.midX, y: attachedRoot.bounds.maxY - 2))
        != nil)

    // Hover peeks a parked Dock open; leaving lets it fall closed again.
    attachedRoot.mouseEntered(with: try enterExitEvent(.mouseEntered))
    #expect(attachedRoot.cameraDockIsExpanded)
    #expect(attachedRoot.cameraDockIsParked)
    attachedRoot.mouseExited(with: try enterExitEvent(.mouseExited))
    #expect(!attachedRoot.cameraDockIsExpanded)

    // Playback opens the Dock, drops the controls band from the tray, and ends parking.
    attachedRoot.updateCameraDockPlaybackState(true, animated: false)
    #expect(attachedRoot.cameraDockIsExpanded)
    #expect(!attachedRoot.cameraDockIsParked)
    let playing = try #require(attachedRoot.cameraDockMaskPath).boundingBoxOfPath
    #expect(abs(playing.minY - (attachedRoot.bounds.minY + 44)) < 0.5)
    #expect(playing.maxY == attachedRoot.bounds.maxY)
    #expect(attachedRoot.grip.alphaValue == 0)
    #expect(attachedRoot.reflection.alphaValue == 1)
    attachedRoot.mouseExited(with: try enterExitEvent(.mouseExited))
    #expect(attachedRoot.cameraDockIsExpanded)
    attachedRoot.updateCameraDockPlaybackState(false, animated: true)
    #expect(try #require(attachedRoot.cameraDockMaskPath).boundingBoxOfPath.minY == 0)
    #expect(attachedRoot.grip.alphaValue == 1)

    // Reduce Motion: no shape motion, only a short crossfade of the content.
    let opacityKey = FloatingRoot.cameraDockContentOpacityAnimationKey
    attachedRoot.cameraDockReduceMotionOverride = true
    attachedRoot.setCameraDockParked(true, animated: true)
    #expect(attachedRoot.cameraDockShapeAnimation == nil)
    let reducedFade = try #require(
      attachedRoot.reflection.layer?.animation(forKey: opacityKey) as? CABasicAnimation)
    #expect(reducedFade.duration == CameraDockMotion.reducedMotionContentDuration)
    #expect(attachedRoot.reflection.alphaValue == 0)
    // Full motion: a spring on the shape, and the content fades in after a short delay.
    attachedRoot.cameraDockReduceMotionOverride = false
    attachedRoot.setCameraDockParked(false, animated: true)
    let open = try #require(attachedRoot.cameraDockShapeAnimation as? CASpringAnimation)
    #expect(abs(open.initialVelocity - CameraDockMotion.expandInitialVelocity) < 1e-6)
    let openFade = try #require(
      attachedRoot.reflection.layer?.animation(forKey: opacityKey) as? CABasicAnimation)
    #expect(openFade.duration == CameraDockMotion.expandContentDuration)
    #expect(openFade.fillMode == .backwards)
    #expect(attachedRoot.reflection.alphaValue == 1)
    attachedRoot.cameraDockReduceMotionOverride = nil

    c.stopPresenting()
    let externalParameters = CameraDockScreenParameters(
      screenFrame: CameraDockRect(
        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
      visibleFrame: CameraDockRect(
        x: screen.visibleFrame.minX, y: screen.visibleFrame.minY,
        width: screen.visibleFrame.width, height: screen.visibleFrame.height),
      safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    let external = syntheticDisplay(
      screen: screen, id: 9002, uuid: "detached-test-display", parameters: externalParameters)
    c.displayProvider = { [external] }
    c.state.selectedDisplay = external.selectionKey
    c.showCameraDock()
    let detachedDock = try #require(c.cameraDock)
    let detachedWindow = try #require(detachedDock.window)
    let detachedRoot = try #require(detachedDock.root)
    let detachedLayer = try #require(detachedRoot.layer)
    let detachedWindowColor = try #require(detachedWindow.backgroundColor.usingColorSpace(.sRGB))
    let detachedLayerColor = try #require(
      detachedLayer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))

    #expect(detachedDock.dockStyle == .detached)
    #expect(detachedWindow.frame.maxY == screen.visibleFrame.maxY - 6)
    #expect(!detachedWindow.isOpaque)
    #expect(detachedWindow.hasShadow)
    #expect(detachedWindowColor.alphaComponent == 0)
    #expect(detachedLayerColor.redComponent > 0 && detachedLayerColor.redComponent < 0.1)
    #expect(detachedLayerColor.greenComponent > 0 && detachedLayerColor.greenComponent < 0.1)
    #expect(detachedLayerColor.blueComponent > 0 && detachedLayerColor.blueComponent < 0.1)
    #expect(detachedRoot.layer?.cornerRadius == 14)
    #expect(detachedLayer.mask is CAShapeLayer)
    let detachedPath = try #require((detachedLayer.mask as? CAShapeLayer)?.path)
    #expect(detachedPath.boundingBoxOfPath == detachedRoot.bounds)
  }

  @Test func explicitCameraDockCollapsePausesWithoutMovingAndPlaybackReexpands() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let frame = screen.frame
    let safeTop = 32.0
    let safeEdge = frame.maxY - safeTop
    let sideWidth = (frame.width - 200) / 2
    let parameters = dockParameters(
      for: screen, safeTop: safeTop, topInset: safeTop,
      left: CameraDockRect(x: frame.minX, y: safeEdge, width: sideWidth, height: safeTop),
      right: CameraDockRect(
        x: frame.minX + sideWidth + 200, y: safeEdge, width: sideWidth, height: safeTop))
    let display = syntheticDisplay(
      screen: screen, id: 9003, uuid: "collapse-test-display", isBuiltIn: true,
      parameters: parameters)
    c.displayProvider = { [display] }
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    let root = try #require(dock.root)
    let viewport = dock.reflection.viewport
    viewport.driver?.stop()
    viewport.driver = nil
    await settle(c)
    #expect(c.session.state == .paused)
    c.state.countdown = 0
    c.session.countdownSeconds = 0
    c.toggle()
    await settle(c)
    #expect(c.session.state == .running)
    let before = try #require(c.authoritative.captureAnchor())

    #expect(root.cameraDockIsExpanded)
    #expect(root.cameraDockPlaybackActive)

    dock.collapseToNotch()
    await settle(c)
    #expect(c.session.state == .paused)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == before.utf16Offset)
    #expect(root.cameraDockIsParked)
    #expect(!root.cameraDockIsExpanded)
    let compactPath = try #require(root.cameraDockMaskPath)
    #expect(compactPath.boundingBoxOfPath.height < root.bounds.height)
    #expect(compactPath.boundingBoxOfPath.maxY == root.bounds.maxY)
    #expect(dock.window?.frame == dock.window?.frame.standardized)

    c.toggle()
    await settle(c)
    #expect(c.session.state == .running)
    #expect(root.cameraDockIsExpanded)
    #expect(!root.cameraDockIsParked)
    let playingPath = try #require(root.cameraDockMaskPath)
    #expect(abs(playingPath.boundingBoxOfPath.minY - (root.bounds.minY + 44)) < 0.5)
    #expect(playingPath.boundingBoxOfPath.maxY == root.bounds.maxY)

    c.toggle()
    await settle(c)
    #expect(c.session.state == .paused)
    #expect(root.cameraDockIsExpanded)
    #expect(try #require(root.cameraDockMaskPath).boundingBoxOfPath.minY == root.bounds.minY)
  }

  @Test func ordinaryFloatingRootRetainsRoundedClipping() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.showFloating()
    let root = try #require(c.floating?.root)
    #expect(root.layer?.cornerRadius == 14)
    #expect(root.layer?.masksToBounds == true)
  }

  @Test func cameraDockPreservesTimedPlaybackAcrossSurfaceChange() async throws {
    let c = try await prepared(200, paragraphText: "Cue")
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    // The end position must survive the switch, so the Dock's column must not reflow the
    // 64 pt "Cue 1xx" paragraphs. The default width on a 1024 pt CI display does; the
    // widest Dock does not.
    c.setCameraDockWidth(CameraDockGeometry.maximumWidth)
    c.state.countdown = 0
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[100])
    try c.session.enableTimed(seconds: 600)
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...40 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    let session = c.session
    let snapshot = try #require(session.snapshot?.id)
    let endTarget = try #require(session.timeline.upperBound)
    let remainingBeforeSwitch = try #require(session.remainingSeconds)
    let expectedFinish = session.elapsedSeconds + remainingBeforeSwitch

    c.showCameraDock()
    let viewport = try #require(c.cameraDock?.reflection.viewport)
    viewport.driver?.stop()
    viewport.driver = nil
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.state == .paused)
    #expect(c.state.cameraDockReady)
    #expect(c.session.timedDuration == 600)
    #expect(c.session === session)
    #expect(c.session.snapshot?.id == snapshot)
    #expect(c.session.elapsedSeconds == 10)
    #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
    #expect(c.session.timeline.upperBound == endTarget)
    #expect(
      abs(c.session.elapsedSeconds + (c.session.remainingSeconds ?? -1) - expectedFinish) <= 1e-6)
    #expect(c.cameraDock != nil)

    c.toggle()
    await settle(c)
    #expect(c.session.state == .running)
    #expect(!c.state.cameraDockReady)

    try c.session.pause()
    time = 40
    c.resumeAfterMeasurement()
    await settle(c)
    #expect(c.session.state == .running)
    #expect(c.session.elapsedSeconds == 10)
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
    #expect(c.session.timeline.upperBound == endTarget)
    #expect(
      abs(c.session.elapsedSeconds + (c.session.remainingSeconds ?? -1) - expectedFinish) <= 1e-6)

    c.setCameraDockLineCount(4)
    await settle(c)
    #expect(c.session.state == .running)
    #expect(c.session.elapsedSeconds == 10)
    #expect(c.session.timedDuration == 600)
    #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
    #expect(c.session.timeline.upperBound == endTarget)
    #expect(
      abs(c.session.elapsedSeconds + (c.session.remainingSeconds ?? -1) - expectedFinish) <= 1e-6)
    c.stop()
  }

  @Test func cameraDockDisplayLossPausesActivePlaybackAndRetainsPosition() async throws {
    let c = try await prepared()
    defer { c.close() }
    let previewSize = c.session.logicalSize
    let display = try #require(DisplayDescriptor.all().first)
    var connected = [display]
    c.displayProvider = { connected }
    c.refreshScreens(connected)
    c.state.selectedDisplay = display.selectionKey
    c.seek(c.session.paragraphPositions[60])
    let snapshot = try #require(c.session.snapshot?.id)
    var time = 0.0
    c.session.clock = { time }
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    for frame in 1...8 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }

    c.showCameraDock()
    let viewport = try #require(c.cameraDock?.reflection.viewport)
    viewport.driver?.stop()
    viewport.driver = nil
    await settle(c)
    #expect(c.cameraDock != nil)
    #expect(c.session.state == .paused)
    #expect(c.state.cameraDockReady)
    time = 4
    try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    let position = c.session.timeline.anchorPosition

    connected = []
    c.screensChanged()
    #expect(c.cameraDock == nil)
    #expect(c.floating == nil)
    #expect(c.output == nil)
    #expect(c.session.state == .paused)
    #expect(c.session.snapshot?.id == snapshot)
    #expect(c.session.timeline.anchorPosition == position)
    #expect(c.state.status == "Camera Dock display disconnected — position retained")
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map == nil)
    #expect(
      c.previewCaption.stringValue
        == "LOCAL PREVIEW · \(Int(previewSize.width)) × \(Int(previewSize.height))")
    #expect(c.previewAspectConstraint?.multiplier == previewSize.height / previewSize.width)
    c.refresh()
    #expect(c.state.status == "Camera Dock display disconnected — position retained")
    #expect(c.preview.placementMapView.isHidden)
    #expect(
      c.previewCaption.stringValue
        == "LOCAL PREVIEW · \(Int(previewSize.width)) × \(Int(previewSize.height))")
  }

  @Test func cameraDockForcedPanelCloseRecomputesExpandedPreviewMap() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let display = syntheticDisplay(
      screen: screen, id: 490, uuid: "forced-close-display",
      parameters: dockParameters(for: screen))
    c.displayProvider = { [display] }
    c.refreshScreens([display])
    c.state.selectedDisplay = display.selectionKey
    let previewSize = c.session.logicalSize
    c.setCameraDockPlacementPreviewExpanded(true)
    let expandedMap = try #require(c.preview.placementMapView.map)
    #expect(c.preview.placementMapView.isHidden)

    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    let anchor = try #require(dock.reflection.viewport.captureAnchor())
    dock.close()
    await settle(c)

    #expect(c.cameraDock == nil)
    #expect(c.floating == nil)
    #expect(c.session.state == .paused)
    #expect(c.session.logicalSize == previewSize)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(c.state.status == "Camera Dock stopped — position retained")
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map?.caption == expandedMap.caption)
    #expect(c.previewCaption.stringValue.contains("LOCAL PREVIEW"))
    #expect(
      abs(
        Double(c.previewAspectConstraint?.multiplier ?? 0) - previewSize.height / previewSize.width)
        < 0.000001)
    c.refresh()
    #expect(c.state.status == "Camera Dock stopped — position retained")
    #expect(c.preview.placementMapView.isHidden)
  }

  @Test func cameraDockSecondOpenReusesPanelAndRepeatedCloseIsSafe() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.state.countdown = 0
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    let window = try #require(dock.window)
    let driver = try #require(dock.reflection.viewport.driver)
    let snapshotID = try #require(c.session.snapshot?.id)
    let anchor = try #require(dock.reflection.viewport.captureAnchor())

    c.showCameraDock()

    #expect(c.cameraDock === dock)
    #expect(c.cameraDock?.window === window)
    #expect(c.cameraDock?.reflection.viewport.driver === driver)
    #expect(c.selectedPresentationSurface == "cameraDock")
    #expect(c.session.snapshot?.id == snapshotID)
    #expect(c.cameraDock?.reflection.viewport.captureAnchor()?.utf16Offset == anchor.utf16Offset)

    c.hideOutput()
    c.hideOutput()
    #expect(c.cameraDock == nil)
    #expect(c.output == nil && c.floating == nil)
    #expect(c.selectedPresentationSurface == "preview")
  }

  @Test func cameraDockUsesSelectedExternalAndLabelsFallbackAccurately() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let parameters = dockParameters(for: screen)
    let mirror = syntheticDisplay(
      screen: screen, id: 101, uuid: "mirrored-camera", isBuiltIn: true, isMirrored: true,
      parameters: parameters)
    let external = syntheticDisplay(
      screen: screen, id: 202, uuid: "selected-external", parameters: parameters)
    let connected = [mirror, external]
    c.displayProvider = { connected }
    c.refreshScreens(connected)
    c.state.selectedDisplay = mirror.selectionKey
    #expect(c.cameraDockTarget(in: connected) == nil)
    #expect(c.cameraDockMenuTitle == "Camera Dock")

    c.state.selectedDisplay = external.selectionKey
    c.refreshScreens(connected)
    #expect(c.cameraDockTarget(in: connected)?.id == external.id)
    #expect(c.cameraDockMenuTitle == "Camera Dock (top of display)")
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    #expect(dock.displayID == external.id)
    #expect(c.cameraDockMenuTitle == "Camera Dock (top of display)")
  }

  @Test func cameraDockLeavesExactlyOneSurfaceActiveAcrossAllSurfaceTypes() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    func expectOneSurface(_ expected: String) {
      let active = [
        c.output != nil, c.floating != nil, c.output == nil && c.floating == nil,
      ].filter { $0 }.count
      #expect(active == 1)
      #expect(c.selectedPresentationSurface == expected)
      #expect(c.output == nil || c.floating == nil)
    }
    expectOneSurface("preview")

    c.showFloating()
    c.floating?.reflection.viewport.driver?.stop()
    c.floating?.reflection.viewport.driver = nil
    await settle(c)
    expectOneSurface("floating")

    c.showCameraDock()
    c.cameraDock?.reflection.viewport.driver?.stop()
    c.cameraDock?.reflection.viewport.driver = nil
    await settle(c)
    expectOneSurface("cameraDock")

    c.showOutput(confirm: { _ in .alertFirstButtonReturn })
    c.output?.reflection.viewport.driver?.stop()
    c.output?.reflection.viewport.driver = nil
    await settle(c)
    expectOneSurface("output")

    c.stopPresenting()
    expectOneSurface("preview")
  }

  @Test func cameraDockExitRestoresPriorFloatingAndOutputSurfaces() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey

    c.showFloating()
    c.floating?.reflection.viewport.driver?.stop()
    c.floating?.reflection.viewport.driver = nil
    await settle(c)
    let floatingAnchor = try #require(c.authoritative.captureAnchor())
    c.showCameraDock()
    c.cameraDock?.reflection.viewport.driver?.stop()
    c.cameraDock?.reflection.viewport.driver = nil
    await settle(c)
    c.stopPresenting()
    await settle(c)
    #expect(c.selectedPresentationSurface == "floating")
    #expect(c.floating?.isCameraDock == false)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == floatingAnchor.utf16Offset)

    c.showOutput(confirm: { _ in .alertFirstButtonReturn })
    c.output?.reflection.viewport.driver?.stop()
    c.output?.reflection.viewport.driver = nil
    await settle(c)
    let outputAnchor = try #require(c.authoritative.captureAnchor())
    c.showCameraDock()
    c.cameraDock?.reflection.viewport.driver?.stop()
    c.cameraDock?.reflection.viewport.driver = nil
    await settle(c)
    let dock = try #require(c.cameraDock)
    let dockWindow = try #require(dock.window)
    let escape = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: dockWindow.windowNumber, context: nil,
        characters: String(UnicodeScalar(NSCarriageReturnCharacter)!),
        charactersIgnoringModifiers: String(UnicodeScalar(NSCarriageReturnCharacter)!),
        isARepeat: false, keyCode: 53))
    #expect(CommandRouter.route(escape, window: dockWindow, controller: c))
    await settle(c)
    #expect(c.selectedPresentationSurface == "output")
    #expect(c.output != nil && c.floating == nil)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == outputAnchor.utf16Offset)
  }

  @Test func cameraDockSwitchPreservesRunningAnchorAndSnapshot() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.state.countdown = 0
    var time = 0.0
    c.session.clock = { time }
    c.seek(c.session.paragraphPositions[72])
    let session = c.session
    let snapshot = try #require(session.snapshot?.id)
    session.countdownSeconds = 0
    try session.toggle(c.script)
    for frame in 1...8 {
      time = Double(frame) / 4
      try session.noteFrame(target: time, end: session.timeline.upperBound)
    }
    let runningAnchor = try #require(c.authoritative.captureAnchor())

    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)

    #expect(c.session === session)
    #expect(session.snapshot?.id == snapshot)
    #expect(session.state == .paused)
    #expect(c.state.cameraDockReady)
    #expect(!c.pendingResume)
    #expect(!session.pendingRevision)
    #expect(dock.reflection.viewport.captureAnchor()?.utf16Offset == runningAnchor.utf16Offset)
    let restored = try #require(dock.reflection.viewport.restore(runningAnchor))
    #expect(abs(session.timeline.anchorPosition - restored) < 1)

    c.toggle()
    await settle(c)
    #expect(session.state == .running)
    c.hideOutput()
    await settle(c)
    #expect(c.selectedPresentationSurface == "preview")
    #expect(session.state == .running)
  }

  @Test func cameraDockScreenParameterCallbackRecomputesWithoutDirtyingDocument() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let originalParameters = dockParameters(for: screen)
    let original = syntheticDisplay(
      screen: screen, id: 301, uuid: "callback-display", parameters: originalParameters)
    var connected = [original]
    c.displayProvider = { connected }
    c.refreshScreens(connected)
    c.state.selectedDisplay = original.selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let frameBefore = try #require(dock.window).frame
    let anchorBefore = try #require(dock.reflection.viewport.captureAnchor())
    let snapshotBefore = try #require(c.session.snapshot?.id)
    let sourceBefore = c.script.source.copy() as! NSAttributedString
    let revisionBefore = c.script.revision
    let editedBefore = c.script.isDocumentEdited
    let nextParameters = dockParameters(for: screen, topInset: 24)
    connected = [
      syntheticDisplay(
        screen: screen, id: original.id, uuid: "callback-display", parameters: nextParameters)
    ]

    c.screensChanged()

    let frameAfter = try #require(dock.window).frame
    #expect(frameAfter.maxY < frameBefore.maxY)
    #expect(abs(frameAfter.maxY - (frameBefore.maxY - 24)) < 0.5)
    #expect(dock.displayID == original.id)
    #expect(c.session.snapshot?.id == snapshotBefore)
    #expect(c.script.source.isEqual(to: sourceBefore))
    #expect(c.script.revision == revisionBefore)
    #expect(c.script.isDocumentEdited == editedBefore)
    #expect(dock.reflection.viewport.captureAnchor()?.utf16Offset == anchorBefore.utf16Offset)
  }

  @Test func cameraDockDisplayReconnectRequiresReselectionAndRestoresUUIDPreferences()
    async throws
  {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let parameters = dockParameters(for: screen)
    let original = syntheticDisplay(
      screen: screen, id: 401, uuid: "reconnect-stage", parameters: parameters)
    var connected = [original]
    c.displayProvider = { connected }
    c.refreshScreens(connected)
    c.state.selectedDisplay = original.selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    c.setCameraDockWidth(520)
    c.setCameraDockLineCount(4)
    c.setCameraDockHorizontalNudge(24)
    await settle(c)
    let anchor = try #require(c.cameraDock?.reflection.viewport.captureAnchor())
    let snapshot = try #require(c.session.snapshot?.id)

    connected = []
    c.screensChanged()
    #expect(c.cameraDock == nil)
    #expect(c.session.state == .paused)
    #expect(c.session.snapshot?.id == snapshot)

    let reconnected = syntheticDisplay(
      screen: screen, id: 402, uuid: "reconnect-stage", parameters: parameters)
    connected = [reconnected]
    c.screensChanged()
    #expect(c.cameraDock == nil)
    #expect(c.state.selectedDisplay == reconnected.selectionKey)
    #expect(c.state.cameraDockWidth == 520)
    #expect(c.state.cameraDockLineCount == 4)
    #expect(c.state.cameraDockHorizontalNudge == 24)

    c.selectPresentationSurface("cameraDock")
    let reopened = try #require(c.cameraDock)
    reopened.reflection.viewport.driver?.stop()
    reopened.reflection.viewport.driver = nil
    await settle(c)
    #expect(reopened.displayID == reconnected.id)
    #expect(
      reopened.dockPreferences
        == CameraDockPreferences(
          width: 520, lineCount: 4, horizontalNudge: 24))
    #expect(c.session.snapshot?.id == snapshot)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(c.session.state == .paused)
  }

  @Test func cameraDockPlacementFailureClosesPausesAndRetainsTake() async throws {
    let c = try await prepared()
    defer { c.close() }
    let previewSize = c.session.logicalSize
    let screen = try #require(NSScreen.screens.first)
    var connected = [
      syntheticDisplay(
        screen: screen, id: 501, uuid: "failure-display", parameters: dockParameters(for: screen))
    ]
    c.displayProvider = { connected }
    c.refreshScreens(connected)
    c.state.selectedDisplay = connected[0].selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let snapshot = try #require(c.session.snapshot?.id)
    let anchor = try #require(dock.reflection.viewport.captureAnchor())
    let safeFrame = try #require(dock.window).frame
    let valid = connected[0].cameraDockParameters
    let tooShort = CameraDockScreenParameters(
      screenFrame: valid.screenFrame,
      visibleFrame: CameraDockRect(
        x: valid.visibleFrame.x, y: valid.visibleFrame.y, width: valid.visibleFrame.width,
        height: 100), safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    connected = [
      syntheticDisplay(
        screen: screen, id: 501, uuid: "failure-display", parameters: tooShort)
    ]

    c.screensChanged()

    #expect(c.cameraDock == nil)
    #expect(c.session.state == .paused)
    #expect(c.session.snapshot?.id == snapshot)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(
      c.state.status
        == "Camera Dock unavailable — position retained. Choose a larger display or reduce text size."
    )
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map == nil)
    #expect(
      c.previewCaption.stringValue
        == "LOCAL PREVIEW · \(Int(previewSize.width)) × \(Int(previewSize.height))")
    #expect(c.previewAspectConstraint?.multiplier == previewSize.height / previewSize.width)
    c.refresh()
    #expect(
      c.state.status
        == "Camera Dock unavailable — position retained. Choose a larger display or reduce text size."
    )
    #expect(c.preview.placementMapView.isHidden)
    #expect(safeFrame.minX.isFinite && safeFrame.minY.isFinite)
    #expect(safeFrame.width.isFinite && safeFrame.height.isFinite)

    connected = [
      syntheticDisplay(
        screen: screen, id: 501, uuid: "failure-display", parameters: valid)
    ]
    c.setCameraDockPlacementPreviewExpanded(true)
    #expect(c.preview.placementMapView.isHidden)
    c.showCameraDock()
    let malformedDock = try #require(c.cameraDock)
    malformedDock.reflection.viewport.driver?.stop()
    malformedDock.reflection.viewport.driver = nil
    await settle(c)
    let malformedSafeFrame = try #require(malformedDock.window).frame
    let malformed = CameraDockScreenParameters(
      screenFrame: CameraDockRect(
        x: .infinity, y: valid.screenFrame.y, width: valid.screenFrame.width,
        height: valid.screenFrame.height),
      visibleFrame: valid.visibleFrame, safeTop: valid.safeTop,
      auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    connected = [
      syntheticDisplay(
        screen: screen, id: 501, uuid: "failure-display", parameters: malformed)
    ]
    c.screensChanged()
    #expect(c.cameraDock == nil)
    #expect(c.session.state == .paused)
    #expect(c.session.snapshot?.id == snapshot)
    #expect(
      c.state.status
        == "Camera Dock unavailable — position retained. Choose a larger display or reduce text size."
    )
    #expect(c.session.logicalSize == previewSize)
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map == nil)
    #expect(
      c.previewCaption.stringValue
        == "LOCAL PREVIEW · \(Int(previewSize.width)) × \(Int(previewSize.height))")
    #expect(c.previewAspectConstraint?.multiplier == previewSize.height / previewSize.width)
    c.refresh()
    #expect(
      c.state.status
        == "Camera Dock unavailable — position retained. Choose a larger display or reduce text size."
    )
    #expect(c.preview.placementMapView.isHidden)
    #expect(malformedSafeFrame.minX.isFinite && malformedSafeFrame.minY.isFinite)
  }

  @Test func cameraDockPlacementPreviewTracksSuccessfulPreferenceEdits() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let display = syntheticDisplay(
      screen: screen, id: 602, uuid: "preview-edit-display",
      parameters: dockParameters(for: screen))
    c.displayProvider = { [display] }
    c.refreshScreens([display])
    c.state.selectedDisplay = display.selectionKey

    let scriptSize = c.session.logicalSize
    let scriptCaption = c.previewCaption.stringValue
    let scriptAspect = try #require(c.previewAspectConstraint).multiplier
    #expect(c.preview.placementMapView.isHidden)

    c.setCameraDockWidth(520)
    c.setCameraDockLineCount(4)
    c.setCameraDockHorizontalNudge(24)
    c.resetCameraDockPreferences()
    #expect(c.preview.placementMapView.isHidden)
    #expect(c.preview.placementMapView.map == nil)
    #expect(c.previewCaption.stringValue == scriptCaption)
    #expect(c.previewAspectConstraint?.multiplier == scriptAspect)
    #expect(c.preview.logicalSize == scriptSize)

    c.setCameraDockPlacementPreviewExpanded(true)
    let initialMap = try #require(c.preview.placementMapView.map)
    c.setCameraDockWidth(520)
    let widthMap = try #require(c.preview.placementMapView.map)
    #expect(widthMap.dock.width != initialMap.dock.width)
    #expect(widthMap == c.cameraDockPlacementMap)

    c.setCameraDockLineCount(4)
    let lineMap = try #require(c.preview.placementMapView.map)
    #expect(lineMap.dock.height != widthMap.dock.height)
    #expect(lineMap.caption.hasSuffix("4 lines"))
    #expect(lineMap == c.cameraDockPlacementMap)

    c.setCameraDockHorizontalNudge(24)
    let nudgeMap = try #require(c.preview.placementMapView.map)
    #expect(nudgeMap.dock.x != lineMap.dock.x)
    #expect(nudgeMap == c.cameraDockPlacementMap)

    c.resetCameraDockPreferences()
    let resetMap = try #require(c.preview.placementMapView.map)
    #expect(c.state.cameraDockLineCount == CameraDockGeometry.defaultLineCount)
    #expect(c.state.cameraDockHorizontalNudge == 0)
    #expect(resetMap != nudgeMap)
    #expect(resetMap == c.cameraDockPlacementMap)
  }

  @Test func openCameraDockNudgeRefreshesMapWithoutChangingPlaybackState() async throws {
    let c = try await prepared()
    defer {
      c.stop()
      c.close()
    }
    let screen = try #require(NSScreen.screens.first)
    let display = syntheticDisplay(
      screen: screen, id: 603, uuid: "open-nudge-display", parameters: dockParameters(for: screen))
    c.displayProvider = { [display] }
    c.refreshScreens([display])
    c.state.selectedDisplay = display.selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let window = try #require(dock.window)
    let pausedMap = try #require(c.preview.placementMapView.map)

    #expect(c.session.state == .paused)
    c.setCameraDockWidth(520)
    await settle(c)
    let resizedMap = try #require(c.preview.placementMapView.map)
    #expect(resizedMap.dock.width != pausedMap.dock.width)
    #expect(resizedMap == c.cameraDockPlacementMap)

    let pausedFrameAfterResize = window.frame
    c.setCameraDockHorizontalNudge(24)
    let updatedPausedMap = try #require(c.preview.placementMapView.map)
    #expect(c.session.state == .paused)
    #expect(window.frame.minX != pausedFrameAfterResize.minX)
    #expect(updatedPausedMap.dock.x != resizedMap.dock.x)
    #expect(
      abs(updatedPausedMap.dock.x - (window.frame.minX - screen.frame.minX) / screen.frame.width)
        < 1e-9)
    #expect(updatedPausedMap == c.cameraDockPlacementMap)

    c.state.countdown = 0
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    await settle(c)
    #expect(c.session.state == .running)
    let runningFrame = window.frame
    let runningMap = try #require(c.preview.placementMapView.map)

    c.setCameraDockHorizontalNudge(48)
    let updatedRunningMap = try #require(c.preview.placementMapView.map)
    #expect(c.session.state == .running)
    #expect(window.frame.minX != runningFrame.minX)
    #expect(updatedRunningMap.dock.x != runningMap.dock.x)
    #expect(
      abs(
        updatedRunningMap.dock.x - (window.frame.minX - screen.frame.minX) / screen.frame.width)
        < 1e-9)
    #expect(updatedRunningMap == c.cameraDockPlacementMap)
  }

  @Test func cameraDockPreferenceControlsClampAndUpdatePlacement() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(NSScreen.screens.first)
    let display = syntheticDisplay(
      screen: screen, id: 601, uuid: "preferences-display", parameters: dockParameters(for: screen))
    c.displayProvider = { [display] }
    c.refreshScreens([display])
    c.state.selectedDisplay = display.selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)

    c.setCameraDockWidth(359)
    #expect(c.state.cameraDockWidth == 360)
    c.setCameraDockWidth(761)
    #expect(c.state.cameraDockWidth == 760)
    c.setCameraDockLineCount(1)
    #expect(c.state.cameraDockLineCount == 2)
    c.setCameraDockLineCount(6)
    #expect(c.state.cameraDockLineCount == 5)
    c.setCameraDockHorizontalNudge(-1000)
    #expect(c.state.cameraDockHorizontalNudge == -120)
    c.setCameraDockHorizontalNudge(1000)
    #expect(c.state.cameraDockHorizontalNudge == 120)
    let window = try #require(dock.window)
    #expect(
      dock.dockPreferences
        == CameraDockPreferences(
          width: 760, lineCount: 5, horizontalNudge: 120))
    #expect(!window.isMovable)
    #expect(!window.isMovableByWindowBackground)
  }

  @Test func cameraDockPromptAndControlsExposeAccessibilityAndKeyboardFocus() async throws {
    let c = try await prepared()
    defer {
      c.stop()
      c.close()
    }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.showCameraDock()
    await settle(c)
    let dock = try #require(c.cameraDock)
    let root = try #require(dock.root)
    let panel = try #require(dock.window)
    root.needsLayout = true
    root.layoutSubtreeIfNeeded()
    let controls = try #require(root.cameraDockControls)
    #expect(root.isAccessibilityElement())
    #expect(root.accessibilityLabel() == "CueGlass prompt")
    #expect(panel.canBecomeKey)
    #expect(root.grip.bounds.width > 0)
    #expect(root.grip.bounds.height > 0)
    #expect(controls.closeButton.frame.width > 0)
    #expect(controls.playbackButton.frame.width > 0)
    #expect(controls.adjustButton.frame.width > 0)
    #expect(!panel.autorecalculatesKeyViewLoop)
    let accessibilityChildren = try #require(root.accessibilityChildren() as? [NSView])
    #expect(
      accessibilityChildren.compactMap { $0.accessibilityLabel() }
        == ["Close Camera Dock", "Play or pause", "Adjust Camera Dock"])
    #expect(controls.closeButton.accessibilityRole() == .button)
    #expect(controls.playbackButton.accessibilityRole() == .button)
    #expect(controls.adjustButton.accessibilityRole() == .popUpButton)
    #expect(controls.closeButton.action != nil)
    #expect(controls.playbackButton.action != nil)
    #expect(controls.adjustButton.menu?.items.contains { $0.title == "Reset Placement" } == true)
    panel.makeKeyAndOrderFront(nil)
    panel.selectNextKeyView(nil)
    #expect(
      [controls.closeButton, controls.playbackButton, controls.adjustButton].contains {
        $0 === panel.firstResponder
      })

    let originalWidth = c.state.cameraDockWidth
    c.setCameraDockWidth(originalWidth - 40)
    let widthBeforeAdjust = c.state.cameraDockWidth
    let wider = try #require(controls.adjustButton.menu?.items.first { $0.title == "Wider" })
    #expect(NSApp.sendAction(wider.action!, to: wider.target, from: wider))
    #expect(c.state.cameraDockWidth == widthBeforeAdjust + 20)
    c.setCameraDockWidth(originalWidth)
    await settle(c)
    c.state.countdown = 0
    c.session.countdownSeconds = 0
    #expect(
      NSApp.sendAction(
        controls.playbackButton.action!, to: controls.playbackButton.target,
        from: controls.playbackButton))
    await settle(c)
    #expect(
      c.session.state == .running,
      "Camera Dock Play action left the session at \(c.session.state): \(c.state.status)")
    #expect(
      NSApp.sendAction(
        controls.playbackButton.action!, to: controls.playbackButton.target,
        from: controls.playbackButton))
    #expect(c.session.state == .paused)

    let originalMap = CommandRouter.map
    defer { CommandRouter.map = originalMap }
    CommandRouter.map = CommandMap()
    #expect(panel.makeFirstResponder(panel.contentView))
    let commandEvent = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "d",
        charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2))
    #expect(CommandRouter.route(commandEvent, window: panel, controller: c))
    #expect(c.cameraDock === dock)

    let operatorWindow = try #require(c.window)
    operatorWindow.makeKeyAndOrderFront(nil)
    #expect(operatorWindow.makeFirstResponder(c.editor))
    c.editor.setSelectedRange(NSRange(location: 0, length: 0))
    let before = c.editor.string
    let space = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: operatorWindow.windowNumber, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    #expect(!CommandRouter.route(space, window: operatorWindow, controller: c))
    c.stop()
    #expect(c.editor.isEditable)
    #expect(operatorWindow.makeFirstResponder(c.editor))
    c.editor.insertText(" ", replacementRange: NSRange(location: 0, length: 0))
    #expect(c.editor.string != before)
  }

  @Test func cameraDockMenuAndShortcutOpenFromPreview() async throws {
    let c = try await prepared()
    defer { c.close() }
    let previousMainMenu = NSApp.mainMenu
    let appDelegate = AppDelegate()
    appDelegate.buildMenu()
    defer { NSApp.mainMenu = previousMainMenu }
    let viewMenu = try #require(
      NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu)
    let cameraDockMenuItem = try #require(
      viewMenu.items.first { $0.title == "Camera Dock" })
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    let operatorWindow = try #require(c.window)
    operatorWindow.makeKeyAndOrderFront(nil)
    #expect(operatorWindow.makeFirstResponder(operatorWindow.contentView))

    let originalMap = CommandRouter.map
    defer { CommandRouter.map = originalMap }
    CommandRouter.map = CommandMap()
    let shortcut = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
        windowNumber: operatorWindow.windowNumber, context: nil, characters: "d",
        charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2))
    #expect(CommandRouter.route(shortcut, window: operatorWindow, controller: c))
    let shortcutDock = try #require(c.cameraDock)
    shortcutDock.reflection.viewport.driver?.stop()
    shortcutDock.reflection.viewport.driver = nil
    await settle(c)
    #expect(appDelegate.current === c)
    viewMenu.update()
    #expect(cameraDockMenuItem.isEnabled)
    #expect(appDelegate.validateMenuItem(cameraDockMenuItem))
    #expect(c.selectedPresentationSurface == "cameraDock")

    c.stopPresenting()
    let menu = c.presentationMenu()
    let menuItem = try #require(
      menu.items.first { $0.action == #selector(OperatorWindowController.cameraDockAction) })
    #expect(menuItem.isEnabled)
    #expect(NSApp.sendAction(menuItem.action!, to: menuItem.target, from: menuItem))
    let menuDock = try #require(c.cameraDock)
    menuDock.reflection.viewport.driver?.stop()
    menuDock.reflection.viewport.driver = nil
    await settle(c)
    #expect(c.selectedPresentationSurface == "cameraDock")
    #expect(c.output == nil)
  }

  @Test func cameraDockMappedKeysAndNumericFieldEditingRespectFocus() async throws {
    let c = try await prepared()
    defer {
      c.stop()
      c.close()
    }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.session.clock = { 0 }
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let panel = try #require(dock.window)
    let root = try #require(dock.root)
    #expect(panel.makeFirstResponder(root))

    let originalMap = CommandRouter.map
    defer { CommandRouter.map = originalMap }
    CommandRouter.map = CommandMap()
    func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [])
      throws -> NSEvent
    {
      try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
          windowNumber: panel.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
    func route(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [])
      throws
    {
      #expect(CommandRouter.route(try key(code, characters, flags), window: panel, controller: c))
    }

    let initialSpeed = c.state.speed
    try route(126, "up")
    #expect(c.state.speed == initialSpeed + c.state.fineStep)
    try route(126, "up", [.shift])
    #expect(c.state.speed == initialSpeed + c.state.fineStep + c.state.jumpStep)
    try route(125, "down", [.shift])
    try route(125, "down")
    #expect(c.state.speed == initialSpeed)

    let initialPosition = c.session.timeline.anchorPosition
    try route(121, "pagedown")
    #expect(c.session.timeline.anchorPosition > initialPosition)
    try route(116, "pageup")
    #expect(c.session.timeline.anchorPosition <= initialPosition)
    try route(124, "right")
    try route(123, "left")
    try route(115, "home")
    #expect(c.session.timeline.anchorPosition == 0)

    try route(15, "r")
    #expect(c.session.timeline.direction == .reverse)
    try route(15, "r")
    #expect(c.session.timeline.direction == .forward)
    c.state.countdown = 0
    c.session.countdownSeconds = 0
    try route(49, " ")
    #expect(c.session.state == .running)
    try route(11, "b")
    #expect(c.session.state == .paused)
    try route(47, ".")
    #expect(c.session.state == .running)
    try route(53, String(UnicodeScalar(NSCarriageReturnCharacter)!), [.command])
    #expect(c.cameraDock == nil)
    #expect(c.selectedPresentationSurface == "preview")

    let operatorWindow = try #require(c.window)
    operatorWindow.makeKeyAndOrderFront(nil)
    operatorWindow.layoutIfNeeded()
    func descendants(of view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap(descendants)
    }
    let contentView = try #require(operatorWindow.contentView)
    let speedField = try #require(
      descendants(of: contentView).compactMap { $0 as? NSTextField }
        .first { $0.placeholderString == "LPM" })
    #expect(operatorWindow.makeFirstResponder(speedField))
    let speedBeforeEdit = c.state.speed
    let up = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: operatorWindow.windowNumber, context: nil, characters: "↑",
        charactersIgnoringModifiers: "↑", isARepeat: false, keyCode: 126))
    #expect(!CommandRouter.route(up, window: operatorWindow, controller: c))
    #expect(c.state.speed == speedBeforeEdit)
    let fieldEditor = try #require(operatorWindow.firstResponder as? NSTextView)
    let oldFieldText = fieldEditor.string
    fieldEditor.insertText("9", replacementRange: NSRange(location: 0, length: 0))
    #expect(fieldEditor.string != oldFieldText)
  }

  @Test func cameraDockFailureNoticesSurviveRefresh() async throws {
    PresentationCoordinator.shared.owner?.stop()
    let preferenceKey = "cameraDockPreferences"
    let priorPreferences = UserDefaults.standard.data(forKey: preferenceKey)
    defer {
      if let priorPreferences {
        UserDefaults.standard.set(priorPreferences, forKey: preferenceKey)
      } else {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
      }
    }
    UserDefaults.standard.set(Data("invalid preferences".utf8), forKey: preferenceKey)
    let malformedDocument = ScriptDocument()
    let preferencesController = OperatorWindowController(document: malformedDocument)
    defer { preferencesController.close() }
    #expect(preferencesController.state.status.contains("Camera Dock settings could not be read"))
    let preferencesStatus = preferencesController.state.status
    preferencesController.refresh()
    #expect(preferencesController.state.status == preferencesStatus)

    let noDisplayController = try await prepared()
    defer {
      noDisplayController.stop()
      noDisplayController.close()
    }
    noDisplayController.displayProvider = { [] }
    noDisplayController.showCameraDock()
    #expect(
      noDisplayController.state.status
        == "No display is available for Camera Dock. Connect or select a display.")
    noDisplayController.refresh()
    #expect(
      noDisplayController.state.status
        == "No display is available for Camera Dock. Connect or select a display.")
    noDisplayController.stop()

    let fitController = try await prepared()
    defer {
      fitController.stop()
      fitController.close()
    }
    let screen = try #require(NSScreen.screens.first)
    let base = dockParameters(for: screen)
    let tooShort = CameraDockScreenParameters(
      screenFrame: base.screenFrame,
      visibleFrame: CameraDockRect(
        x: base.visibleFrame.x, y: base.visibleFrame.y, width: base.visibleFrame.width,
        height: 100), safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    let display = syntheticDisplay(
      screen: screen, id: 701, uuid: "too-short-display", parameters: tooShort)
    fitController.displayProvider = { [display] }
    fitController.refreshScreens([display])
    fitController.state.selectedDisplay = display.selectionKey
    fitController.showCameraDock()
    #expect(
      fitController.state.status
        == "Camera Dock does not fit this display. Choose a larger display or reduce text size.")
    fitController.refresh()
    #expect(
      fitController.state.status
        == "Camera Dock does not fit this display. Choose a larger display or reduce text size.")
  }

  @Test func cameraDockFailedFirstOpenPreservesIdleStateAndPreferences() async throws {
    PresentationCoordinator.shared.owner?.stop()
    let preferenceKey = "cameraDockPreferences"
    let priorPreferences = UserDefaults.standard.data(forKey: preferenceKey)
    defer {
      if let priorPreferences {
        UserDefaults.standard.set(priorPreferences, forKey: preferenceKey)
      } else {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
      }
    }
    let displayUUID = "failed-first-open-display"
    var catalog = CameraDockPreferenceCatalog()
    catalog.set(
      CameraDockPreferences(width: 620, lineCount: 5, horizontalNudge: 75),
      forDisplayUUID: displayUUID)
    let savedPreferences = try JSONEncoder().encode(catalog)
    UserDefaults.standard.set(savedPreferences, forKey: preferenceKey)

    let screen = try #require(NSScreen.screens.first)
    let base = dockParameters(for: screen)
    let tooShort = CameraDockScreenParameters(
      screenFrame: base.screenFrame,
      visibleFrame: CameraDockRect(
        x: base.visibleFrame.x, y: base.visibleFrame.y, width: base.visibleFrame.width,
        height: 100),
      safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    let display = syntheticDisplay(
      screen: screen, id: 702, uuid: displayUUID, parameters: tooShort)

    func checkFailure(display: DisplayDescriptor?, notice: String) async throws {
      let document = ScriptDocument()
      document.source = NSAttributedString(string: "An idle take must remain idle.")
      let controller = OperatorWindowController(document: document)
      defer {
        controller.stop()
        controller.close()
      }
      controller.session.clock = { 0 }
      controller.displayProvider = { display.map { [$0] } ?? [] }
      if let display { controller.state.selectedDisplay = display.selectionKey }
      controller.state.cameraDockWidth = 470
      controller.state.cameraDockLineCount = 2
      controller.state.cameraDockHorizontalNudge = -35

      #expect(controller.session.state == .idle)
      #expect(PresentationCoordinator.shared.owner == nil)
      let windowsBefore = presentationWindowIDs()
      controller.showCameraDock()

      #expect(controller.session.state == .idle)
      #expect(controller.session.snapshot == nil)
      #expect(PresentationCoordinator.shared.owner == nil)
      #expect(presentationWindowIDs() == windowsBefore)
      #expect(controller.selectedPresentationSurface == "preview")
      #expect(controller.output == nil)
      #expect(controller.floating == nil)
      #expect(controller.cameraDock == nil)
      #expect(controller.state.cameraDockWidth == 470)
      #expect(controller.state.cameraDockLineCount == 2)
      #expect(controller.state.cameraDockHorizontalNudge == -35)
      #expect(UserDefaults.standard.data(forKey: preferenceKey) == savedPreferences)
      #expect(controller.state.status == notice)
      controller.refresh()
      #expect(controller.state.status == notice)
      #expect(controller.session.state == .idle)
      #expect(PresentationCoordinator.shared.owner == nil)
    }

    try await checkFailure(
      display: nil,
      notice: "No display is available for Camera Dock. Connect or select a display.")
    try await checkFailure(
      display: display,
      notice: "Camera Dock does not fit this display. Choose a larger display or reduce text size.")
  }

  @Test func cameraDockFailedFirstOpenPreservesRunningFloatingSurface() async throws {
    PresentationCoordinator.shared.owner?.stop()
    let preferenceKey = "cameraDockPreferences"
    let priorPreferences = UserDefaults.standard.data(forKey: preferenceKey)
    defer {
      if let priorPreferences {
        UserDefaults.standard.set(priorPreferences, forKey: preferenceKey)
      } else {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
      }
    }
    let displayUUID = "failed-running-open-display"
    var catalog = CameraDockPreferenceCatalog()
    catalog.set(
      CameraDockPreferences(width: 620, lineCount: 5, horizontalNudge: 75),
      forDisplayUUID: displayUUID)
    let savedPreferences = try JSONEncoder().encode(catalog)
    UserDefaults.standard.set(savedPreferences, forKey: preferenceKey)

    let screen = try #require(NSScreen.screens.first)
    let base = dockParameters(for: screen)
    let tooShort = CameraDockScreenParameters(
      screenFrame: base.screenFrame,
      visibleFrame: CameraDockRect(
        x: base.visibleFrame.x, y: base.visibleFrame.y, width: base.visibleFrame.width,
        height: 100),
      safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
    let display = syntheticDisplay(
      screen: screen, id: 703, uuid: displayUUID, parameters: tooShort)

    func checkFailure(display: DisplayDescriptor?, notice: String) async throws {
      let controller = try await prepared(20)
      defer {
        controller.stop()
        controller.close()
      }
      controller.displayProvider = { display.map { [$0] } ?? [] }
      if let display { controller.state.selectedDisplay = display.selectionKey }
      controller.showFloating()
      let floating = try #require(controller.floating)
      let window = try #require(floating.window)
      floating.reflection.viewport.driver?.stop()
      floating.reflection.viewport.driver = nil
      await settle(controller)

      controller.session.clock = { 0 }
      controller.session.countdownSeconds = 0
      try controller.session.toggle(controller.script)
      #expect(controller.session.state == .running)
      #expect(PresentationCoordinator.shared.owner === controller)
      let snapshotID = try #require(controller.session.snapshot?.id)
      let position = controller.session.timeline.anchorPosition
      let elapsed = controller.session.elapsedSeconds
      let remaining = controller.session.remainingSeconds
      controller.state.cameraDockWidth = 470
      controller.state.cameraDockLineCount = 2
      controller.state.cameraDockHorizontalNudge = -35
      let windowsBefore = presentationWindowIDs()

      controller.showCameraDock()

      #expect(controller.session.state == .running)
      #expect(controller.session.snapshot?.id == snapshotID)
      #expect(controller.session.timeline.anchorPosition == position)
      #expect(controller.session.elapsedSeconds == elapsed)
      #expect(controller.session.remainingSeconds == remaining)
      #expect(PresentationCoordinator.shared.owner === controller)
      #expect(presentationWindowIDs() == windowsBefore)
      #expect(controller.floating === floating)
      #expect(floating.window === window)
      #expect(window.isVisible)
      #expect(controller.output == nil)
      #expect(controller.cameraDock == nil)
      #expect(controller.selectedPresentationSurface == "floating")
      #expect(controller.state.cameraDockWidth == 470)
      #expect(controller.state.cameraDockLineCount == 2)
      #expect(controller.state.cameraDockHorizontalNudge == -35)
      #expect(UserDefaults.standard.data(forKey: preferenceKey) == savedPreferences)
      #expect(controller.state.status == notice)
      controller.refresh()
      #expect(controller.state.status == notice)
      #expect(controller.session.state == .running)
      #expect(PresentationCoordinator.shared.owner === controller)
      #expect(controller.floating === floating)
    }

    try await checkFailure(
      display: nil,
      notice: "No display is available for Camera Dock. Connect or select a display.")
    try await checkFailure(
      display: display,
      notice: "Camera Dock does not fit this display. Choose a larger display or reduce text size.")
  }

  @Test func cameraDockCommandWithoutDocumentDoesNotOpenDocumentPicker() throws {
    let previousMainMenu = NSApp.mainMenu
    let appDelegate = AppDelegate()
    appDelegate.buildMenu()
    defer { NSApp.mainMenu = previousMainMenu }
    let viewMenu = try #require(
      NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu)
    let cameraDockMenuItem = try #require(
      viewMenu.items.first { $0.title == "Camera Dock" })
    #expect(appDelegate.current == nil)
    viewMenu.update()
    #expect(!cameraDockMenuItem.isEnabled)
    #expect(!appDelegate.validateMenuItem(cameraDockMenuItem))
    for siblingItem in viewMenu.items where siblingItem !== cameraDockMenuItem {
      #expect(appDelegate.validateMenuItem(siblingItem))
    }

    let panel = PresentationPanel(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    defer { panel.close() }
    let documentsBefore = NSDocumentController.shared.documents.count
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "d",
        charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2))
    #expect(!CommandRouter.route(event, window: panel, controller: nil))
    appDelegate.cameraDockAction()
    #expect(NSDocumentController.shared.documents.count == documentsBefore)
    #expect(PresentationCoordinator.shared.owner == nil)
    #expect(
      !NSApp.windows.contains {
        $0.isVisible && ($0 is PresentationPanel || $0 is OutputWindow)
      })
  }

  @Test func cameraDockCanOpenForAnEmptyScriptWithoutStartingPlayback() async throws {
    let document = ScriptDocument()
    document.source = NSAttributedString(string: "")
    let c = OperatorWindowController(document: document)
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey

    c.selectPresentationSurface("cameraDock")
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)

    #expect(c.script.source.string.isEmpty)
    #expect(c.session.snapshot != nil)
    #expect(c.session.state != .running)
    #expect(!c.session.timeline.running)
    #expect(c.cameraDock != nil)
    #expect(
      CameraDockGrip(state: c.state, controller: c).statusText == "Ready")
    #expect(!CameraDockGrip(state: c.state, controller: c).canPlay)
    #expect(dock.root?.cameraDockControls?.playbackButton.isEnabled == false)
  }

  @Test func cameraDockDoesNotRequestMicrophoneAndTimedPlaybackWorksWhenDenied()
    async throws
  {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    let source = CameraDockVoiceCaptureProbe()
    let microphone = CameraDockMicrophoneProbe(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: c.session, source: source, microphone: microphone,
      usageDescription: { "Microphone access is used only for Follow Voice." })
    c.voiceCoordinator = coordinator
    await coordinator.refreshAvailability()
    #expect(coordinator.state == .ready)

    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)

    c.startVoiceFollow()
    for _ in 0..<1000 where coordinator.state != .microphoneDenied { await mainTurn() }
    #expect(coordinator.state == .microphoneDenied)
    #expect(microphone.requestCount == 1)
    #expect(source.startCount == 0)

    var time = 0.0
    c.session.clock = { time }
    c.session.countdownSeconds = 0
    try c.session.enableTimed(seconds: 600)
    #expect(c.session.timedDuration == 600)
    try c.session.toggle(c.script)
    #expect(c.session.state == .running)
    for frame in 1...4 {
      time = Double(frame) / 4
      try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
    }
    #expect(c.session.timedDuration == 600)
    #expect(c.session.elapsedSeconds == 1)
    #expect(microphone.requestCount == 1)
    #expect(source.startCount == 0)
  }

  @Test func cameraDockFollowVoiceUsesDockLineMapAndManualSeekStopsCapture() async throws {
    let document = ScriptDocument()
    document.source = NSAttributedString(
      string: "North wind carries the lantern home.\nEast wind carries the harbor light.")
    let c = OperatorWindowController(document: document)
    defer {
      c.stop()
      c.close()
    }
    let display = try #require(DisplayDescriptor.all().first)
    c.displayProvider = { [display] }
    c.refreshScreens([display])
    c.state.selectedDisplay = display.selectionKey
    var playbackTime = 0.0
    c.session.clock = { playbackTime }
    try c.session.prepare(document)
    c.render()
    await settle(c)

    let session = c.session
    let snapshot = try #require(session.snapshot)
    let displayWidth = CameraDockGeometry.defaultWidth(
      screenWidth: Double(display.screen.frame.width))
    c.showFloating()
    let floating = try #require(c.floating)
    floating.reflection.viewport.driver?.stop()
    floating.reflection.viewport.driver = nil
    await settle(c)
    let floatingWindow = try #require(floating.window)
    floatingWindow.setContentSize(CGSize(width: displayWidth, height: 320))
    c.floatingResized()
    await settle(c)
    let floatingTable = try #require(c.authoritative.voiceLineTable)

    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let table = try #require(c.authoritative.voiceLineTable)
    #expect(c.session === session)
    #expect(c.session.snapshot?.id == snapshot.id)
    #expect(floatingTable.lines.map(\.utf16Range) == table.lines.map(\.utf16Range))
    let index = ScriptIndex(text: snapshot.attributed.string)
    let expectedToken = try #require(index.tokens.first { $0.text == "home" })
    let floatingY = try #require(floatingTable.y(for: expectedToken))
    let expectedY = try #require(table.y(for: expectedToken))
    #expect(abs(floatingY - expectedY) < 0.5)

    let source = CameraDockVoiceCaptureProbe()
    let time = 0.0
    let coordinator = VoiceFollowCoordinator(
      session: c.session, source: source, microphone: CameraDockMicrophoneProbe(.granted),
      usageDescription: { "Microphone access is used only for Follow Voice." },
      captureClock: { time })
    c.voiceCoordinator = coordinator
    await coordinator.refreshAvailability()
    #expect(
      await awaitVoiceUpdate(
        coordinator, matching: { coordinator.state == .listening }, label: "listening",
        perform: { c.startVoiceFollow() }))
    #expect(coordinator.state == .listening)
    #expect(source.startCount == 1)

    let words = ["North", "wind", "carries", "the", "lantern", "home"]
      .enumerated().map { offset, text in
        let start = Double(offset) * 0.25
        return RecognizedWord(text: text, start: start, end: start + 0.2, confidence: 0.9)
      }
    let eventEnd = try #require(words.last?.end)
    let initialVoiceCeiling = try #require(c.session.timeline.voiceCeiling)
    #expect(expectedY > initialVoiceCeiling + 0.5)
    #expect(
      await awaitVoiceUpdate(
        coordinator,
        matching: {
          guard let ceiling = c.session.timeline.voiceCeiling else { return false }
          return ceiling > initialVoiceCeiling + 0.5 && abs(ceiling - expectedY) < 0.5
        },
        label: "finalized speech alignment advances the initial ceiling",
        perform: {
          source.send(
            TranscriptEvent(
              isFinal: true, rangeStart: 0, rangeEnd: eventEnd, availableAt: eventEnd,
              words: words, finalizedThrough: eventEnd))
        }))
    let ceiling = try #require(c.session.timeline.voiceCeiling)
    #expect(abs(ceiling - expectedY) < 0.5)
    #expect(c.session.snapshot?.id == snapshot.id)

    playbackTime = 100
    let positionBeforeUncertainSpeech = try c.session.timeline.position(at: playbackTime)
    #expect(abs(positionBeforeUncertainSpeech - ceiling) < 0.5)
    let uncertainStart = eventEnd + 0.25
    let uncertainWords = (0..<8).map { offset in
      let start = uncertainStart + Double(offset) * 0.25
      return RecognizedWord(
        text: "unrecognized", start: start, end: start + 0.2, confidence: 0.1)
    }
    let uncertainEnd = try #require(uncertainWords.last?.end)
    #expect(
      await awaitVoiceUpdate(
        coordinator,
        matching: { coordinator.state == .holding("Unsure — holding") },
        label: "low-confidence hold",
        perform: {
          source.send(
            TranscriptEvent(
              isFinal: true, rangeStart: uncertainStart, rangeEnd: uncertainEnd,
              availableAt: uncertainEnd, words: uncertainWords,
              finalizedThrough: uncertainEnd))
        }))
    #expect(c.session.timeline.voiceCeiling == ceiling)

    #expect(
      await awaitVoiceUpdate(
        coordinator,
        matching: { coordinator.state == .holding("Waiting for speech") },
        label: "silence hold after explicit monotonic-time advance",
        perform: { Task { await coordinator.advanceSilence(to: uncertainEnd + 1.3) } }))
    #expect(c.session.timeline.voiceCeiling == ceiling)

    c.seek(100)
    #expect(c.session.voiceSuspended)
    #expect(coordinator.state == .suspended("Manual navigation"))
    #expect(source.stopCount == 1)
    #expect(c.session.timeline.anchorPosition == 100)
  }

  @Test func cameraDockUsesOnlyThePreparedSnapshotWhenSourceFileIsAbsent() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    let missingURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(
        ".build/camera-dock-source-that-does-not-exist.cueflow")
    #expect(!FileManager.default.fileExists(atPath: missingURL.path))
    c.script.fileURL = missingURL
    let snapshot = try #require(c.session.snapshot)
    let source = c.script.source.copy() as! NSAttributedString
    let anchor = try #require(c.authoritative.captureAnchor())

    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)

    #expect(!FileManager.default.fileExists(atPath: missingURL.path))
    #expect(c.session.snapshot?.id == snapshot.id)
    #expect(c.session.snapshot?.attributed == snapshot.attributed)
    #expect(c.script.source.isEqual(to: source))
    #expect(dock.reflection.viewport.captureAnchor()?.utf16Offset == anchor.utf16Offset)
  }

  @Test func malformedImportDoesNotReplaceTheActiveCameraDockTake() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.showCameraDock()
    let dock = try #require(c.cameraDock)
    dock.reflection.viewport.driver?.stop()
    dock.reflection.viewport.driver = nil
    await settle(c)
    let snapshot = try #require(c.session.snapshot)
    let source = c.script.source.copy() as! NSAttributedString
    let anchor = try #require(dock.reflection.viewport.captureAnchor())

    #expect(throws: (any Error).self) {
      try c.script.read(
        from: Data("not a CueGlass document".utf8), ofType: ScriptDocument.nativeType)
    }

    #expect(c.cameraDock === dock)
    #expect(c.session.snapshot?.id == snapshot.id)
    #expect(c.session.snapshot?.attributed == snapshot.attributed)
    #expect(c.script.source.isEqual(to: source))
    #expect(dock.reflection.viewport.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(c.script.saveBlockedReason != nil)
  }

  @Test func cameraDockExplainerDisclosesHousingAndScreenRecordingBehavior() {
    #expect(
      OperatorWindowController.cameraDockExplainer.contains("never covers the camera housing"))
    #expect(OperatorWindowController.cameraDockExplainer.contains("visible in screen recordings"))
    #expect(
      OperatorWindowController.cameraDockExplainer.contains(
        "does not access the camera or microphone"))
  }

  @Test func cameraDockEdgeFadeKeepsTheCameraFacingEdgeOpaque() throws {
    let snapshot = ScriptSnapshot(
      id: UUID(), documentID: UUID(), revision: 0, attributed: NSAttributedString(string: "Prompt"))
    var style = ReadingStyle()
    style.edgeFadeFraction = 0.2
    let viewport = PrompterViewport(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
    viewport.configure(
      snapshot: snapshot, style: style, size: CGSize(width: 360, height: 180),
      guideFractionOverride: 0.2, fadesTopEdge: false)
    #expect(viewport.topPadding == 36)
    let mask = try #require(viewport.scroll.layer?.mask as? CAGradientLayer)
    let colors = try #require(mask.colors as? [CGColor])
    #expect(colors.count == 4)
    #expect(colors[0].alpha == 0)
    #expect(colors[1].alpha == 1)
    #expect(colors[2].alpha == 1)
    #expect(colors[3].alpha == 1)
    #expect(mask.startPoint.y == (mask.isGeometryFlipped ? 1 : 0))
    #expect(mask.endPoint.y == (mask.isGeometryFlipped ? 0 : 1))
    #expect(mask.locations?.map(\.doubleValue) == [0, 0.2, 0.8, 1])
  }

  @Test func infeasibleRestartCancelsPlanAndAllowsManualPlay() async throws {
    let c = try await prepared()
    defer { c.close() }
    c.seek(c.session.paragraphPositions[180])
    try c.session.enableTimed(seconds: 100)
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.timedDuration == 100)
    c.restart()
    #expect(c.session.timedDuration == nil)
    #expect(c.session.timeline.anchorPosition == 0)
    #expect(c.session.elapsedSeconds == 0)
    #expect(c.session.state == .paused)
    #expect(c.session.message.contains("maximum"))
    #expect(c.state.status.contains("maximum"))
    c.state.countdown = 0
    c.toggle()
    #expect(c.session.state == .running)
    #expect(c.session.timedDuration == nil)
    #expect(c.session.effectiveLPM >= 2 && c.session.effectiveLPM <= 240)
  }
  @Test func atomicLayoutResolvesOnlyFinalGeometry() throws {
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(ScriptDocument())
    try session.updateLayout(end: 10000, paragraphs: [0], wordCount: 100, lineCount: 100)
    try session.seek(9000)
    try session.enableTimed(seconds: 100)
    // The interim 0/100000 geometry is infeasible; the final 99000/100000 is feasible.
    try session.updateLayout(
      end: 100000, paragraphs: [0], wordCount: 1000, lineCount: 1000, position: 99000)
    #expect(session.timeline.anchorPosition == 99000)
    #expect(session.timedDuration == 100)
    #expect(abs((session.remainingSeconds ?? -1) - 100) < 0.00001)
  }
  @Test func pendingTimedPlanHonorsManualCancellation() async throws {
    for reverse in [false, true] {
      let c = try await prepared()
      defer { c.close() }
      c.seek(c.session.paragraphPositions[180])
      try c.session.enableTimed(seconds: 100)
      var style = c.state.style
      style.fontSize = 120
      c.changeStyle(style)
      #expect(c.session.measuring)
      if reverse { c.execute(.reverse) } else { c.setSpeed(40) }
      await settle(c)
      #expect(c.session.timedDuration == nil)
      if !reverse { #expect(c.session.preferredLPM == 40) }
    }
  }
  @Test func realFloatingSwitchAndResizeKeepRunning() async throws {
    let c = try await prepared()
    defer { c.close() }
    c.seek(c.session.paragraphPositions[100])
    let anchor = try #require(c.authoritative.captureAnchor())
    let snapshot = c.session.snapshot?.id
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    c.showFloating()
    c.floating?.reflection.viewport.driver?.stop()
    c.floating?.reflection.viewport.driver = nil
    #expect(c.floating != nil)
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.state == .running)
    #expect(c.session.countdownDigit == nil)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    let window = try #require(c.floating?.window)
    window.setContentSize(CGSize(width: 600, height: 350))
    c.floatingResized()
    #expect(c.session.measuring)
    window.setContentSize(CGSize(width: 700, height: 400))
    c.floatingResized()
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.state == .running)
    #expect(c.session.countdownDigit == nil)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(c.session.snapshot?.id == snapshot)
  }
  @Test func realOutputSwitchRestoresAndResumes() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    c.seek(c.session.paragraphPositions[180])
    let anchor = try #require(c.authoritative.captureAnchor())
    let snapshot = c.session.snapshot?.id
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    c.showOutput(confirm: { _ in .alertFirstButtonReturn })
    let output = try #require(c.output)
    #expect(output.window?.ignoresMouseEvents == true)
    output.reflection.viewport.driver?.stop()
    output.reflection.viewport.driver = nil
    #expect(c.session.measuring)
    await settle(c)
    #expect(c.session.state == .running)
    #expect(c.session.countdownDigit == nil)
    #expect(c.authoritative.captureAnchor()?.utf16Offset == anchor.utf16Offset)
    #expect(c.session.snapshot?.id == snapshot)
  }

  @Test func voiceSurfaceChangesStayPausedUntilExplicitResume() async throws {
    let c = try await prepared()
    defer { c.close() }
    let display = try #require(DisplayDescriptor.all().first)
    c.state.selectedDisplay = display.selectionKey
    try c.session.beginVoice(epoch: 1)

    c.showFloating()
    c.floating?.reflection.viewport.driver?.stop()
    c.floating?.reflection.viewport.driver = nil
    await settle(c)
    #expect(c.session.voiceSessionActive)
    #expect(c.session.voiceSuspended)
    #expect(c.session.state == .paused)
    #expect(!c.session.timeline.running)
    #expect(!c.pendingResume)

    let floatingWindow = try #require(c.floating?.window)
    floatingWindow.setContentSize(CGSize(width: 680, height: 380))
    c.floatingResized()
    await settle(c)
    #expect(c.session.state == .paused)
    #expect(!c.session.timeline.running)
    #expect(!c.pendingResume)

    c.showCameraDock()
    c.cameraDock?.reflection.viewport.driver?.stop()
    c.cameraDock?.reflection.viewport.driver = nil
    await settle(c)
    #expect(c.cameraDock != nil)
    #expect(c.session.voiceSessionActive)
    #expect(c.session.voiceSuspended)
    #expect(c.session.state == .paused)
    #expect(!c.session.timeline.running)
    #expect(!c.pendingResume)

    c.showOutput(confirm: { _ in .alertFirstButtonReturn })
    c.output?.reflection.viewport.driver?.stop()
    c.output?.reflection.viewport.driver = nil
    await settle(c)
    #expect(c.session.voiceSessionActive)
    #expect(c.session.voiceSuspended)
    #expect(c.session.state == .paused)
    #expect(!c.session.timeline.running)
    #expect(!c.pendingResume)

    c.resumeAfterMeasurement()
    #expect(c.session.state == .paused)
    #expect(!c.session.timeline.running)
  }

  @Test func fullscreenMatteTracksPreviewWithoutChangingFloatingAlpha() throws {
    let controller = OperatorWindowController(document: ScriptDocument())
    defer { controller.close() }
    let display = try #require(DisplayDescriptor.all().first)
    let output = OutputWindowController(display: display)
    defer { output.close() }
    controller.output = output
    controller.session.logicalSize = display.screen.frame.size
    controller.render()
    let window = try #require(output.window)
    let viewport = output.reflection.viewport
    func expectMatte(_ expected: [Double], panelAlpha: Double) throws {
      let matte = try #require(window.backgroundColor.usingColorSpace(.sRGB))
      #expect(abs(matte.redComponent - expected[0]) < 0.00001)
      #expect(abs(matte.greenComponent - expected[1]) < 0.00001)
      #expect(abs(matte.blueComponent - expected[2]) < 0.00001)
      #expect(matte.alphaComponent == 1)
      #expect(window.isOpaque)
      #expect(window.alphaValue == 1)
      let previewColor = try #require(controller.preview.layer?.backgroundColor)
      #expect(NSColor(cgColor: previewColor)?.usingColorSpace(.sRGB) == matte)
      // Both margins expose the window matte, independently of the panel alpha.
      #expect(viewport.panelBackground.frame.minX > 0)
      #expect(viewport.panelBackground.frame.maxX < viewport.bounds.maxX)
      #expect(viewport.layer?.backgroundColor?.alpha == 0)
      #expect(
        abs((viewport.panelBackground.layer?.backgroundColor?.alpha ?? -1) - panelAlpha) < 0.00001)
    }
    try expectMatte([0.039, 0.039, 0.043], panelAlpha: 1)
    var style = controller.state.style
    style.backgroundRGBA = [0.2, 0.3, 0.4, 1]
    style.textPanelOpacity = 0.25
    let layouts = viewport.layoutCount
    controller.changeStyle(style)
    #expect(viewport.layoutCount == layouts)
    try expectMatte([0.2, 0.3, 0.4], panelAlpha: 0.25)
    style.fontSize = 96
    controller.changeStyle(style)
    try expectMatte([0.2, 0.3, 0.4], panelAlpha: 0.25)
    controller.output = nil
    let floating = FloatingPrompterWindowController(screen: display.screen, controller: controller)
    defer { floating.close() }
    controller.floating = floating
    controller.state.floatingOpacity = 0.3
    controller.updateFloatingOptions()
    controller.render()
    #expect(floating.window?.isOpaque == false)
    #expect(floating.window?.backgroundColor?.alphaComponent == 0.02)
    #expect(floating.window?.alphaValue == 0.3)
    #expect(floating.reflection.viewport.layer?.backgroundColor?.alpha == 0)
    #expect(
      abs((floating.reflection.viewport.panelBackground.layer?.backgroundColor?.alpha ?? -1) - 0.25)
        < 0.00001)
    controller.floating = nil
  }
  @Test func quietStudioCompositionPreservesSource() throws {
    let doc = ScriptDocument()
    let controller = OperatorWindowController(document: doc)
    let window = try #require(controller.window)
    window.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    controller.inspectorItem?.isCollapsed = false
    controller.balancePanes()
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(abs((controller.editor.enclosingScrollView?.frame.width ?? 0) - 420) < 2)
    #expect(abs(controller.stageView.frame.width - 578) < 2)
    // Layout rounds the preview to whole points; its height stays within half a
    // point of the logical 16:9 output, whose exact size is asserted below.
    let previewSize = controller.preview.bounds.size
    #expect(
      abs(
        previewSize.height - previewSize.width * controller.session.logicalSize.height
          / controller.session.logicalSize.width) <= 0.5)
    let source = doc.source.copy() as! NSAttributedString
    let derived = PresentationBuilder.build(source, style: controller.state.style)
    let paragraph = try #require(
      derived.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    #expect(paragraph.minimumLineHeight == 0)
    #expect(paragraph.maximumLineHeight == 0)
    try controller.session.prepare(doc)
    controller.render()
    controller.refresh()
    #expect(controller.editor.showsTake)
    #expect(!controller.editor.isEditable)
    controller.editor.currentTakeOffset = 10
    controller.editor.displayIfNeeded()
    #expect(doc.source == source)
    #expect(controller.editor.attributedString() == source)
    try controller.session.seek(100)
    controller.applyCurrentPosition()
    window.setFrame(CGRect(x: 100, y: 100, width: 1002, height: 800), display: false)
    controller.balancePanes()
    controller.preview.layoutSubtreeIfNeeded()
    #expect(controller.preview.reflection.viewport.currentPosition == 100)
    #expect(abs(controller.preview.reflection.viewport.scroll.contentView.bounds.minY - 100) < 0.5)
    controller.stop()
    #expect(!controller.editor.showsTake)
    #expect(controller.editor.isEditable)
    let logical = controller.session.logicalSize
    var narrow = window.frame
    narrow.size = CGSize(width: 980, height: 640)
    window.setFrame(narrow, display: false)
    controller.balancePanes()
    #expect(window.frame.width == 980)
    #expect(window.frame.height == 640)
    #expect(controller.inspectorItem?.isCollapsed == true)
    #expect(controller.stageView.frame.width >= 420)
    #expect(controller.editor.typingAttributes[.paragraphStyle] is NSParagraphStyle)
    #expect(controller.preview.logicalSize == logical)
    #expect(abs(controller.preview.reflection.bounds.width - logical.width) < 1e-9)
    #expect(abs(controller.preview.reflection.viewport.frame.width - logical.width) < 1e-9)
    controller.close()
  }
  @Test func rejectedReloadAndAtomicReplacement() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".build/d3/reload", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: root) } catch let error as NSError {
        Issue.record("Cleanup failed: \(error.code)")
      }
    }
    for bytes in [Data("not JSON".utf8), Data("{\"formatVersion\":2}".utf8)] {
      let doc = ScriptDocument()
      let before = doc.source
      let url = root.appendingPathComponent("reload.cueflow")
      try bytes.write(to: url)
      doc.fileURL = url
      #expect(throws: (any Error).self) {
        try doc.read(from: url, ofType: ScriptDocument.nativeType)
      }
      #expect(doc.source == before)
      #expect(throws: (any Error).self) {
        try doc.writeSafely(
          to: url, ofType: ScriptDocument.nativeType, for: .autosaveInPlaceOperation)
      }
      #expect(try Data(contentsOf: url) == bytes)
      try doc.writeSafely(
        to: root.appendingPathComponent("copy.cueflow"), ofType: ScriptDocument.nativeType,
        for: .saveToOperation)
    }
    let doc = ScriptDocument()
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.toggle(doc)
    try session.noteFrame(target: 0.2, end: nil)
    try session.pause()
    let id = session.snapshot?.id
    let position = try session.position(at: 0.2)
    let timeline = session.timeline
    session.pendingRevision = true
    doc.cloudStatus = .notDownloaded
    #expect(throws: (any Error).self) { try session.loadLatest(doc) }
    #expect(session.snapshot?.id == id)
    #expect(session.state == .paused)
    #expect(session.timeline == timeline)
    #expect(session.pendingRevision)
    #expect(try session.position(at: 30) == position)
  }
  @Test func paceUsesLaidOutLineAdvance() throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: String(repeating: "one two three four five six seven eight ", count: 50))
    let controller = OperatorWindowController(document: doc)
    controller.session.clock = { 0 }
    try controller.session.prepare(doc)
    controller.render()
    for (size, multiplier) in [18.0, 64, 120, 180].flatMap({ size in [1.0, 2.0].map { (size, $0) } }
    ) {
      var style = controller.state.style
      style.fontSize = size
      style.lineHeightMultiplier = multiplier
      #expect(
        try SpeedModel(lpm: 240, lineAdvance: PresentationFont.lineAdvance(style)).limitedByLayout
          == false)
      style.paragraphSpacing = 0
      controller.changeStyle(style)
      let fragment = try #require(
        controller.authoritative.text.textLayoutManager?.textLayoutFragment(
          for: CGPoint(x: 0, y: 0)))
      let lines = fragment.textLineFragments
      #expect(lines.count >= 2)
      let pitch = lines[1].typographicBounds.minY - lines[0].typographicBounds.minY
      #expect(abs(controller.session.timeline.velocity * 60 / pitch - 30) < 0.3)
      #expect(controller.session.preferredLPM == 30)
    }
    controller.close()
  }
  @Test func countdownTimingAndAids() throws {
    let doc = ScriptDocument()
    let controller = OperatorWindowController(document: doc)
    var time = 0.0
    controller.session.clock = { time }
    try controller.session.prepare(doc)
    controller.render()
    controller.session.countdownSeconds = 3
    try controller.session.toggle(doc)
    #expect(controller.session.state == .countingDown)
    try controller.session.noteFrame(target: 2, end: 1000)
    #expect(try controller.session.position(at: 2) == 0)
    try controller.session.noteFrame(target: 3, end: 1000)
    #expect(controller.session.state == .running)
    #expect(try controller.session.position(at: 3) == 0)
    time = 3
    try controller.session.pause()
    #expect(controller.session.elapsedSeconds == 0)
    let count = controller.authoritative.layoutCount
    var style = controller.state.style
    style.edgeFadeFraction = 0.2
    style.readingGuideOpacity = 0.3
    style.textPanelOpacity = 0.7
    controller.changeStyle(style)
    #expect(controller.authoritative.layoutCount == count)
    style.sideMarginFraction = 0.1
    controller.changeStyle(style)
    #expect(controller.authoritative.layoutCount == count + 1)
    controller.close()
  }
  @Test func studioGeometryPanelAndHiddenKeys() throws {
    let doc = ScriptDocument()
    let controller = OperatorWindowController(document: doc)
    let window = try #require(controller.window)
    window.makeKeyAndOrderFront(nil)
    for width in [980.0, 1002, 1280] {
      window.setContentSize(CGSize(width: width, height: 740))
      controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
      window.contentView?.layoutSubtreeIfNeeded()
      #expect(controller.stageView.bounds.width >= 419)
      #expect(controller.editor.enclosingScrollView?.frame.width ?? 0 >= 319)
      if width == 980 { #expect(controller.inspectorItem?.isCollapsed == true) }
      #expect(controller.stageView.bounds.height >= window.contentLayoutRect.height * 0.85)
    }
    controller.session.clock = { 0 }
    controller.state.countdown = 0
    controller.toggle()
    controller.showFloating()
    controller.showControls()
    window.orderOut(nil)
    let panel = try #require(controller.panel?.window)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(nil)
    let before = controller.state.speed
    let up = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil,
        characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
        charactersIgnoringModifiers: String(UnicodeScalar(NSUpArrowFunctionKey)!), isARepeat: false,
        keyCode: 126))
    panel.keyDown(with: up)
    #expect(controller.state.speed == before + 1)
    let b = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "b",
        charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
    panel.keyDown(with: b)
    #expect(controller.session.state == .paused)
    controller.showFloating()
    #expect(controller.output == nil)
    #expect(controller.floating != nil)
    let id = controller.session.snapshot?.id
    controller.state.floatingOpacity = 0.3
    controller.updateFloatingOptions()
    #expect(controller.floating?.window?.alphaValue == 0.3)
    #expect(!controller.state.contrastWarning.isEmpty)
    #expect(controller.session.snapshot?.id == id)
    controller.stop()
    controller.close()
  }
  @Test func chunkedActualEndMeasurement() async throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<10000).map { "Line \($0): one two three four five six seven eight" }.joined(
        separator: "\n"))
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(doc)
    let viewport = PrompterViewport(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    viewport.configure(
      snapshot: try #require(session.snapshot), style: session.style,
      size: CGSize(width: 1280, height: 720))
    let result: (Double, Int, Int) = await withCheckedContinuation { continuation in
      viewport.measure { end, _, words, lines in continuation.resume(returning: (end, words, lines))
      }
    }
    #expect(result.0 > 720)
    #expect(result.1 == 100000)
    #expect(result.2 >= 10000)
    #expect(viewport.measurementChunkCount > 1)
    print(
      "MEASUREMENT 100000 words, chunks=\(viewport.measurementChunkCount), totalSeconds=\(viewport.measurementTotalSeconds), worstChunkSeconds=\(viewport.measurementWorstSeconds)"
    )
  }
  @Test func timedFinishReverseAndNavigation() throws {
    let doc = ScriptDocument()
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(doc)
    try session.updateLayout(
      end: 15000, paragraphs: [0, 100, 300], wordCount: 1000, lineCount: 100)
    try session.enableTimed(seconds: 300)
    try session.toggle(doc)
    for step in 1...1200 { try session.noteFrame(target: Double(step) / 4, end: 15000) }
    #expect(session.state == .paused)
    #expect(try session.position(at: 300) == 15000)
    #expect(abs(session.elapsedSeconds - 300) < 0.000001)
    try session.toggle(doc)
    #expect(session.state == .paused)
    try session.restart()
    #expect(session.timeline.direction == .forward)
    #expect(session.elapsedSeconds == 0)
    #expect(try session.position(at: 300) == 0)
    try session.speed(60)
    #expect(session.timedDuration == nil)
    #expect(session.message.contains("disabled"))
    try session.seek(150)
    try session.toggle(doc)
    try session.step(forward: false)
    #expect(session.state == .running)
    #expect(session.timeline.anchorPosition == 100)
    try session.step(forward: true)
    #expect(session.timeline.anchorPosition == 300)
    try session.scrub(delta: 20, momentum: false)
    #expect(session.state == .paused)
    #expect(session.timeline.anchorPosition == 320)
    try session.toggle(doc)
    let before = session.timeline.anchorPosition
    try session.scrub(delta: 100, momentum: true)
    #expect(session.timeline.anchorPosition == before)
    try session.pause()
    try session.seek(100)
    try session.reverse()
    try session.speed(50 * 60 / session.lineAdvance)
    try session.toggle(doc)
    for step in 1...4 { try session.noteFrame(target: 300 + Double(step) * 0.5, end: 15000) }
    #expect(session.state == .paused)
    #expect(session.timeline.anchorPosition == 0)
    try session.restart()
    session.countdownSeconds = 5
    try session.toggle(doc)
    #expect(session.state == .countingDown)
    try session.toggle(doc)
    #expect(session.state == .paused)
    #expect(session.countdownEnd == nil)
  }
  @Test func savedMissingFontAndNativeUndo() throws {
    let doc = ScriptDocument()
    doc.model.readingStyle.fontIdentifier = "CueFlow-Definitely-Not-Installed-Font"
    let controller = OperatorWindowController(document: doc)
    #expect(controller.state.status.localizedCaseInsensitiveContains("font"))
    let before = doc.source.string
    controller.editor.undoManager?.removeAllActions()
    controller.editor.undoManager?.beginUndoGrouping()
    controller.editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
    controller.editor.undoManager?.endUndoGrouping()
    controller.editor.undoManager?.undo()
    #expect(controller.editor.string == before)
    #expect(doc.source.string == before)
    controller.close()
  }
}

extension OperatorFeatureTests {
  private func voicePlaybackSession() throws -> PlaybackSession {
    let document = ScriptDocument()
    document.source = NSAttributedString(string: "North wind carries the lantern home.")
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(document)
    return session
  }

  @Test func voiceDisplayStallPausesAtTheLastPresentedFrame() throws {
    var now = 0.0
    let session = try voicePlaybackSession()
    session.clock = { now }
    try session.beginVoice(epoch: 1)
    try session.voiceGlide(to: 500, epoch: 1)
    let expectedPresentedPosition = session.timeline.velocity * 0.2
    try session.noteFrame(target: 0.2, end: 1000)

    now = 2
    try session.noteFrame(target: 2, end: 1000)

    #expect(session.voiceSessionActive)
    #expect(session.voiceSuspended)
    #expect(session.state == .paused)
    #expect(abs(session.timeline.anchorPosition - expectedPresentedPosition) < 0.001)
    #expect(abs(session.elapsedSeconds - 0.2) < 0.001)
  }

  @Test func rejectedTrackpadMomentumDoesNotSuspendVoice() throws {
    let session = try voicePlaybackSession()
    try session.beginVoice(epoch: 1)

    try session.scrub(delta: 100, momentum: true)

    #expect(session.voiceSessionActive)
    #expect(!session.voiceSuspended)
    #expect(session.state == .running)
    #expect(session.timeline.anchorPosition == 0)
  }

  @Test func resumedVoiceIgnoresMomentumFromThePreviousScrub() throws {
    let session = try voicePlaybackSession()
    try session.beginVoice(epoch: 1)
    try session.scrub(delta: 20, momentum: false)
    #expect(session.voiceSuspended)
    try session.resumeVoice(epoch: session.voiceEpoch)
    let resumedPosition = session.timeline.anchorPosition

    try session.scrub(delta: 20, momentum: true)

    #expect(session.voiceSessionActive)
    #expect(!session.voiceSuspended)
    #expect(session.state == .running)
    #expect(session.timeline.anchorPosition == resumedPosition)
  }
}

// Fix9 ports the Q3 intent matrix and Q4 settled-geometry oracle. Keep the
// inherited suite above byte unchanged; these tests share its serialization.
extension OperatorFeatureTests {
  @Test func displaySelectionRemapsWhenDisplayIDChanges() async throws {
    let c = try await prepared()
    defer { c.close() }
    let screen = try #require(DisplayDescriptor.all().first?.screen)
    let oldDisplay = DisplayDescriptor(
      screen: screen, preference: .init(uuid: "stable-display", name: "Stage"), id: 101)
    let reconnectedDisplay = DisplayDescriptor(
      screen: screen, preference: .init(uuid: "stable-display", name: "Stage"), id: 202)

    // Seed the controller's display-key-to-preference map before selecting this
    // synthetic display so a persisted disconnected preference cannot shadow it.
    c.refreshScreens([oldDisplay])
    c.state.selectedDisplay = oldDisplay.selectionKey
    c.refreshScreens([])
    c.refreshScreens([reconnectedDisplay])

    #expect(c.state.selectedDisplay == reconnectedDisplay.selectionKey)
    #expect(c.state.displays == [reconnectedDisplay.selectionKey])
    #expect(c.state.status.hasPrefix(c.session.message))
  }

  private func preparationTurn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
  private func preparationController(paragraphs: Int = 300) async throws
    -> OperatorWindowController
  {
    let c = try await prepared(paragraphs)
    c.state.countdown = 0
    c.seek(c.session.paragraphPositions[100])
    return c
  }
  private func stopPreparationDriver(_ c: OperatorWindowController) {
    for viewport in [c.output?.reflection.viewport, c.floating?.reflection.viewport] {
      viewport?.driver?.stop()
      viewport?.driver = nil
    }
  }
  private func showPreparationSurface(_ c: OperatorWindowController, kind: String) throws {
    if kind == "output" {
      let display = try #require(DisplayDescriptor.all().first)
      c.state.selectedDisplay = display.selectionKey
      c.showOutput(confirm: { _ in .alertFirstButtonReturn })
    } else {
      c.showFloating()
    }
    stopPreparationDriver(c)
  }
  private func startPreparation(_ c: OperatorWindowController, kind: String) async throws {
    c.session.countdownSeconds = 0
    try c.session.toggle(c.script)
    try showPreparationSurface(c, kind: kind)
    if kind == "resize" {
      await settle(c)
      let window = try #require(c.floating?.window)
      window.setContentSize(CGSize(width: 600, height: 350))
      c.floatingResized()
    }
  }
  private func enterPreparationPass(_ c: OperatorWindowController, second: Bool) async throws {
    // configure clears the end; pass 1 publishes it before pass 2 starts.
    // Inspect this existing observation without driving or querying layout.
    if second {
      for _ in 0..<20 {
        if c.authoritative.endPosition != nil { break }
        await preparationTurn()
      }
    }
    try #require(c.session.measuring)
    #expect((c.authoritative.endPosition != nil) == second)
    print(
      "FIX9 preparation pass=\(second ? 2 : 1) chunks=\(c.authoritative.measurementChunkCount)")
  }
  private func expectPreparationInvariants(
    _ c: OperatorWindowController, snapshot: UUID?, source: String
  ) {
    #expect(!c.session.measuring && !c.pendingPlay && !c.pendingResume)
    #expect(c.session.snapshot?.id == snapshot)
    #expect(c.script.source.string == source)
    #expect(c.session.preferredLPM == 30)
  }
  private func expectSettledPreparationGeometry(_ c: OperatorWindowController) async throws {
    // Record ALL product values before any observational layout query.
    let bound = try #require(c.session.timeline.upperBound)
    let cache = c.authoritative.endPosition
    let position = c.session.timeline.anchorPosition
    let paragraph = try #require(c.session.paragraphPositions.dropFirst(100).first)
    let measured = c.authoritative
    func pass() async -> (Double, [Double]) {
      await withCheckedContinuation { continuation in
        measured.measure { end, paragraphs, _, _ in
          continuation.resume(returning: (end, paragraphs))
        }
      }
    }
    let first = await pass()
    _ = measured.captureAnchor()
    let settled = await pass()
    print(
      "FIX9 geometry bound=\(bound) cache=\(String(describing: cache)) position=\(position) paragraph=\(paragraph) pass1=\(first.0) settled=\(settled.0)"
    )
    #expect(abs(bound - settled.0) < 0.00001)
    if let cache { #expect(abs(cache - bound) < 0.00001) }
    #expect(abs(position - paragraph) < 0.00001)
    let settledParagraph = try #require(settled.1.dropFirst(100).first)
    #expect(abs(paragraph - settledParagraph) < 0.00001)
  }
  @Test func laterPauseWinsDuringBothPreparationPasses() async throws {
    for kind in ["floating", "output"] {
      for second in [false, true] {
        for action in ["hide", "sleep", "restart", "scrub", "displayLoss"] {
          let c = try await preparationController()
          defer { c.close() }
          let snapshot = c.session.snapshot?.id
          let source = c.script.source.string
          try await startPreparation(c, kind: kind)
          try await enterPreparationPass(c, second: second)
          #expect(c.pendingResume)
          switch action {
          case "hide": c.hideOutput()
          case "sleep": c.sleeping()
          case "restart": c.restart()
          case "scrub": c.scrub(delta: -10, momentum: false)
          default: c.handleAvailableDisplayIDs([])
          }
          let intended = c.session.timeline.anchorPosition
          #expect(c.session.state == .paused)
          await settle(c)
          print("FIX9 pause \(kind) \(action) pass=\(second ? 2 : 1) state=\(c.session.state)")
          #expect(c.session.state == .paused)
          #expect(c.session.countdownDigit == nil)
          if action == "restart" || action == "scrub" {
            #expect(c.session.timeline.anchorPosition == intended)
          }
          if action == "restart" { #expect(c.session.timeline.anchorPosition == 0) }
          expectPreparationInvariants(c, snapshot: snapshot, source: source)
        }
      }
    }
  }
  @Test func runningNavigationSurvivesBothPreparationPasses() async throws {
    for second in [false, true] {
      for action in ["seek", "next", "previous", "reverse"] {
        // Keep both bounded passes observable even on faster or slower hosted Macs.
        let c = try await preparationController(paragraphs: 700)
        defer { c.close() }
        let snapshot = c.session.snapshot?.id
        let source = c.script.source.string
        try await startPreparation(c, kind: "floating")
        try await enterPreparationPass(c, second: second)
        switch action {
        case "seek": c.seek(1000)
        case "next": c.execute(.nextParagraph)
        case "previous": c.execute(.previousParagraph)
        default: c.execute(.reverse)
        }
        let intended = c.session.timeline.anchorPosition
        await settle(c)
        #expect(c.session.state == .running && c.session.countdownDigit == nil)
        #expect(c.session.timeline.anchorPosition == intended)
        if action == "reverse" { #expect(c.session.timeline.direction == .reverse) }
        expectPreparationInvariants(c, snapshot: snapshot, source: source)
      }
    }
  }
  @Test func sleepingCancelsOperatorPlayAndMinimizeCancelsPreviewResume() async throws {
    let c = try await preparationController()
    defer { c.close() }
    c.state.countdown = 5
    var style = c.state.style
    style.fontSize = 120
    c.changeStyle(style)
    c.toggle()
    #expect(c.session.measuring && c.pendingPlay && !c.pendingResume)
    c.sleeping()
    await settle(c)
    #expect(c.session.state == .paused && c.session.countdownDigit == nil)
    #expect(!c.pendingPlay && !c.pendingResume)
    #expect(c.session.message == "Paused for sleep")

    let preview = try await preparationController()
    defer { preview.close() }
    preview.session.countdownSeconds = 0
    try preview.session.toggle(preview.script)
    try preview.session.pause()
    preview.render()
    preview.resumeAfterMeasurement()
    #expect(preview.session.measuring && preview.pendingResume)
    preview.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
    await settle(preview)
    #expect(preview.session.state == .paused && preview.session.countdownDigit == nil)
    #expect(!preview.pendingPlay && !preview.pendingResume)
  }
  @Test func anotherDocumentClaimCancelsPreparationWithoutSilentResume() async throws {
    for second in [false, true] {
      let c = try await preparationController()
      defer { c.close() }
      try await startPreparation(c, kind: "floating")
      try await enterPreparationPass(c, second: second)
      let other = OperatorWindowController(document: ScriptDocument())
      defer { other.close() }
      #expect(throws: NSError.self) { try PresentationCoordinator.shared.claim(other) }
      #expect(PresentationCoordinator.shared.owner === c)
      #expect(c.session.state == .paused)
      await settle(c)
      #expect(c.session.state == .paused && c.session.countdownDigit == nil)
      #expect(!c.pendingPlay && !c.pendingResume)
      #expect(c.session.message == "Another document requested presentation. Stop this take first.")
      #expect(other.session.state == .idle)
    }
  }
  @Test func closeHandoffInstallsSettledEndAndParagraphAnchorInBothPasses() async throws {
    for kind in ["floating", "output", "resize", "outputLoss"] {
      for second in [false, true] {
        let c = try await preparationController(paragraphs: 300)
        defer { c.close() }
        try await startPreparation(c, kind: kind == "outputLoss" ? "output" : kind)
        try await enterPreparationPass(c, second: second)
        if kind == "outputLoss" { c.handleAvailableDisplayIDs([]) } else { c.hideOutput() }
        await settle(c)
        #expect(c.session.state == .paused)
        #expect(!c.pendingPlay && !c.pendingResume)
        print("FIX9 close geometry \(kind) pass=\(second ? 2 : 1)")
        try await expectSettledPreparationGeometry(c)
      }
    }
  }
  @Test func timedCloseKeepsOriginalBudgetMessageAndSettledEnd() async throws {
    for kind in ["floating", "output"] {
      for second in [false, true] {
        let c = try await preparationController(paragraphs: 300)
        defer { c.close() }
        var time = 0.0
        c.session.clock = { time }
        try c.session.enableTimed(seconds: 600)
        c.session.countdownSeconds = 0
        try c.session.toggle(c.script)
        for frame in 1...40 {
          time = Double(frame) / 4
          try c.session.noteFrame(target: time, end: c.session.timeline.upperBound)
        }
        try showPreparationSurface(c, kind: kind)
        try await enterPreparationPass(c, second: second)
        #expect(c.pendingResume)
        c.hideOutput()
        await settle(c)
        #expect(c.session.state == .paused)
        #expect(c.session.timedDuration == 600)
        #expect(abs((c.session.remainingSeconds ?? -1) - 590) < 0.00001)
        #expect(c.session.elapsedSeconds == 10)
        #expect(c.session.countdownDigit == nil)
        #expect(!c.pendingPlay && !c.pendingResume)
        #expect(
          c.session.message
            == (kind == "floating"
              ? "Floating prompter stopped" : "Output stopped — position retained"))
        // Timed playback advanced from paragraph 100 before preparation; compare
        // its saved anchor rather than requiring the old paragraph's position.
        let bound = try #require(c.session.timeline.upperBound)
        let cache = c.authoritative.endPosition
        let position = c.session.timeline.anchorPosition
        let message = c.session.message
        let measured = c.authoritative
        func pass() async -> Double {
          await withCheckedContinuation { continuation in
            measured.measure { end, _, _, _ in continuation.resume(returning: end) }
          }
        }
        _ = await pass()
        _ = measured.captureAnchor()
        let settled = await pass()
        print(
          "FIX9 timed close \(kind) pass=\(second ? 2 : 1) bound=\(bound) cache=\(String(describing: cache)) position=\(position) settled=\(settled) message=\(message)"
        )
        #expect(abs(bound - settled) < 0.00001)
        if let cache { #expect(abs(cache - bound) < 0.00001) }
      }
    }
  }
}

extension OperatorFeatureTests {
  @Test func nativeRestingMinimumAndExplicitCollapse() throws {
    // The saved user-collapse preference is read at init; pin it in the volatile
    // argument domain so the outcome never depends on a prior run's defaults.
    let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    UserDefaults.standard.setVolatileDomain(
      arguments.merging(["inspectorCollapsed": false]) { $1 }, forName: UserDefaults.argumentDomain)
    defer {
      UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
    let controller = OperatorWindowController(document: ScriptDocument())
    defer { controller.close() }
    let window = try #require(controller.window)
    let content = try #require(window.contentView)
    // A user drag holds the window width at dragThatCanResizeWindow (510); the
    // narrowest width it can reach is the content fitting width under that pull,
    // measured from the balanced 1280 x 800 state a drag starts from.
    func dragMinimum() -> CGFloat {
      let drag = content.widthAnchor.constraint(equalToConstant: 0)
      drag.priority = .dragThatCanResizeWindow
      drag.isActive = true
      defer { drag.isActive = false }
      return content.fittingSize.width
    }
    window.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    controller.inspectorItem?.isCollapsed = false
    controller.balancePanes()
    content.layoutSubtreeIfNeeded()
    #expect(window.minSize.width == 980)
    #expect(abs((controller.editor.enclosingScrollView?.frame.width ?? 0) - 420) < 2)
    #expect(abs(controller.stageView.frame.width - 578) < 2)
    #expect(abs((controller.inspectorItem?.viewController.view.frame.width ?? 0) - 280) < 2)
    #expect(dragMinimum() <= 1002)
    controller.inspectorWidthConstraint?.isActive = false
    controller.inspectorItem?.isCollapsed = true
    content.layoutSubtreeIfNeeded()
    #expect(dragMinimum() <= 980)
    window.setFrame(CGRect(x: 100, y: 100, width: 1002, height: 800), display: false)
    controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
    #expect(controller.inspectorItem?.isCollapsed == false)
    controller.toggleInspector()
    #expect(controller.inspectorItem?.isCollapsed == true)
    window.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
    #expect(controller.inspectorItem?.isCollapsed == true)
  }

  @Test func nativeChromeLeavesFirstRowsUncovered() throws {
    let controller = OperatorWindowController(document: ScriptDocument())
    defer { controller.close() }
    let window = try #require(controller.window)
    window.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    controller.inspectorItem?.isCollapsed = false
    controller.balancePanes()
    let content = try #require(window.contentView)
    content.layoutSubtreeIfNeeded()
    let bar = try #require(controller.takeBar)
    let inspector = try #require(controller.inspectorItem?.viewController.view)
    let host = try #require(inspector.subviews.first)
    let scroll = try #require(controller.editor.enclosingScrollView)
    // Retain J4's structural preconditions before checking foreground paint order.
    #expect(window.styleMask.contains(.fullSizeContentView))
    #expect(
      abs(
        bar.frame.maxY
          - (controller.stageView.bounds.maxY - controller.stageView.safeAreaInsets.top)) < 0.5)
    #expect(abs(host.frame.maxY - (inspector.bounds.maxY - inspector.safeAreaInsets.top)) < 0.5)
    #expect(scroll.contentInsets.top == scroll.safeAreaInsets.top)
    func pinnedToSafeArea(_ view: NSView, parent: NSView) -> Bool {
      parent.constraints.contains {
        $0.isActive && $0.firstItem as? NSView === view && $0.firstAttribute == .top
          && $0.secondItem as? NSLayoutGuide === parent.safeAreaLayoutGuide
          && $0.secondAttribute == .top
      }
    }
    #expect(pinnedToSafeArea(bar, parent: controller.stageView))
    #expect(pinnedToSafeArea(host, parent: inspector))
    let manager = try #require(controller.editor.textLayoutManager)
    let range = try #require(manager.textContentManager?.documentRange)
    manager.ensureLayout(for: range)
    let fragment = try #require(manager.textLayoutFragment(for: range.location))
    let firstText = controller.editor.convert(
      fragment.layoutFragmentFrame.offsetBy(
        dx: controller.editor.textContainerOrigin.x, dy: controller.editor.textContainerOrigin.y),
      to: nil)
    // The inspector host is flipped; take its first 24 pt row in window space.
    let hostRect = host.convert(host.bounds, to: nil)
    let firstRow = CGRect(
      x: hostRect.minX, y: hostRect.maxY - 24, width: hostRect.width, height: 24)
    let split = controller.splitController.splitView
    let dividerHitSlop = max(4, split.dividerThickness)
    let theme = try #require(content.superview)
    // An occluder paints after the target's owner in view order, belongs to
    // neither the owner's subtree, its ancestors nor the owner's own split
    // column, and overlaps the target. Exclude the actual system divider;
    // its width can differ across supported macOS versions.
    func paintsAfter(_ a: NSView, _ b: NSView) -> Bool {
      func chain(_ view: NSView) -> [NSView] {
        var result: [NSView] = []
        var current: NSView? = view
        while let v = current {
          result.insert(v, at: 0)
          current = v.superview
        }
        return result
      }
      let pa = chain(a)
      let pb = chain(b)
      var i = 0
      while i < min(pa.count, pb.count), pa[i] === pb[i] { i += 1 }
      guard i > 0, i < pa.count, i < pb.count else { return false }
      let siblings = pa[i - 1].subviews
      return (siblings.firstIndex(of: pa[i]) ?? -1) > (siblings.firstIndex(of: pb[i]) ?? -1)
    }
    let targets: [(NSView, CGRect)] = [
      (bar, bar.convert(bar.bounds, to: nil)), (controller.editor, firstText), (host, firstRow),
    ]
    var stack: [NSView] = [theme]
    var occluders: [String] = []
    while let view = stack.popLast() {
      stack.append(contentsOf: view.subviews)
      guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { continue }
      let rect = view.convert(view.bounds, to: nil)
      for (owner, target) in targets {
        let column = split.arrangedSubviews.first { owner.isDescendant(of: $0) }
        if view === owner || view.isDescendant(of: owner) || owner.isDescendant(of: view) {
          continue
        }
        if let column, view.isDescendant(of: column) { continue }
        let overlap = rect.intersection(target.insetBy(dx: dividerHitSlop, dy: 0))
        if !overlap.isNull, overlap.width > 0, overlap.height > 0, paintsAfter(view, owner) {
          occluders.append("\(type(of: view)) \(rect) over \(target)")
        }
      }
    }
    #expect(occluders.isEmpty, "\(occluders)")
  }

  @Test func controlsResponderChainKeepsParagraphAndFineKeys() async throws {
    let controller = try await prepared(20)
    defer { controller.close() }
    controller.state.fineStep = 1
    controller.showControls()
    controller.window?.orderOut(nil)
    let panel = try #require(controller.panel?.window)
    panel.makeKeyAndOrderFront(nil)
    for _ in 0..<20 {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    print(
      "J4 responder key=\(panel.isKeyWindow) responder=\(String(describing: panel.firstResponder))")
    let pace = controller.state.speed
    func send(_ code: UInt16, _ character: Int) throws {
      let text = String(UnicodeScalar(character)!)
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: panel.windowNumber, context: nil, characters: text,
          charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
      panel.sendEvent(event)
    }
    let initial = controller.session.timeline.anchorPosition
    try send(121, NSPageDownFunctionKey)
    #expect(controller.session.timeline.anchorPosition > initial)
    #expect(controller.state.speed == pace)
    try send(116, NSPageUpFunctionKey)
    #expect(controller.session.timeline.anchorPosition == initial)
    #expect(controller.state.speed == pace)
    try send(126, NSUpArrowFunctionKey)
    #expect(controller.state.speed == pace + 1)
    try send(125, NSDownArrowFunctionKey)
    #expect(controller.state.speed == pace)
  }
}

extension OperatorFeatureTests {
  @Test func nativeEditorUndoRestoresCleanDocumentStatus() async throws {
    let doc = ScriptDocument()
    doc.makeWindowControllers()
    let controller = try #require(doc.windowControllers.first as? OperatorWindowController)
    defer { controller.close() }

    let original = doc.source.copy() as! NSAttributedString
    #expect(!doc.isDocumentEdited)

    let undo = try #require(controller.editor.undoManager)
    #expect(undo === doc.undoManager)
    undo.removeAllActions()
    undo.beginUndoGrouping()
    controller.editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
    controller.editor.insertText("Y", replacementRange: NSRange(location: 1, length: 0))
    controller.editor.insertText("Z", replacementRange: NSRange(location: 2, length: 0))
    undo.endUndoGrouping()
    await preparationTurn()
    let edited = controller.editor.attributedString()
    #expect(doc.source == edited)
    #expect(doc.isDocumentEdited)

    undo.undo()
    await preparationTurn()
    #expect(controller.editor.attributedString() == original)
    #expect(doc.source == original)
    #expect(!doc.isDocumentEdited)

    undo.redo()
    await preparationTurn()
    #expect(controller.editor.attributedString() == edited)
    #expect(doc.source == edited)
    #expect(doc.isDocumentEdited)

    undo.undo()
    await preparationTurn()
    #expect(controller.editor.attributedString() == original)
    #expect(doc.source == original)
    #expect(!doc.isDocumentEdited)
  }
}

extension OperatorFeatureTests {
  @Test func metadataRefreshPreservesEditorSelection() throws {
    let doc = ScriptDocument()
    let controller = OperatorWindowController(document: doc)
    defer { controller.close() }
    let selected = NSRange(location: 4, length: 8)
    controller.editor.setSelectedRange(selected)
    let source = controller.editor.attributedString()

    NotificationCenter.default.post(name: ScriptDocument.replaced, object: doc)

    #expect(controller.editor.selectedRange() == selected)
    #expect(controller.editor.attributedString() == source)
  }

  @Test func timedScrollingRequestWaitsForInitialMeasurement() async throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<200).map { "Paragraph \($0) alpha beta gamma delta epsilon" }.joined(
        separator: "\n"))
    let controller = OperatorWindowController(document: doc)
    defer { controller.close() }

    controller.enableTimedScrolling(seconds: 600)
    #expect(controller.session.measuring)
    #expect(controller.pendingTimedDuration == 600)
    #expect(controller.state.status.contains("Timed Scrolling will be set when ready"))

    await settle(controller)

    #expect(controller.pendingTimedDuration == nil)
    #expect(controller.session.timedDuration == 600)
    #expect(controller.session.timeline.upperBound != nil)
  }

  @Test func manualPaceCancelsPendingTimedScrollingStatus() async throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<200).map { "Paragraph \($0) alpha beta gamma delta epsilon" }.joined(
        separator: "\n"))
    let controller = OperatorWindowController(document: doc)
    defer { controller.close() }

    controller.enableTimedScrolling(seconds: 600)
    #expect(controller.session.measuring)
    #expect(controller.state.status.contains("Timed Scrolling will be set when ready"))

    controller.setSpeed(40)

    #expect(controller.pendingTimedDuration == nil)
    #expect(controller.state.status.contains("request canceled by manual pace change"))
    await settle(controller)
    #expect(controller.session.timedDuration == nil)
    #expect(!controller.state.status.contains("will be set when ready"))
  }

  @Test func readingPaceUndoAndRedoSynchronizeTheTake() async throws {
    let controller = try await prepared(20)
    defer { controller.close() }
    let undo = try #require(controller.editor.undoManager)
    undo.removeAllActions()
    let original = controller.script.model.preferredSpeedLinesPerMinute
    let changed = original + 10

    controller.setSpeed(changed)
    #expect(controller.script.model.preferredSpeedLinesPerMinute == changed)
    #expect(controller.state.speed == changed)
    #expect(controller.session.preferredLPM == changed)

    undo.undo()
    #expect(controller.script.model.preferredSpeedLinesPerMinute == original)
    #expect(controller.state.speed == original)
    #expect(controller.session.preferredLPM == original)
    #expect(undo.canRedo)

    undo.redo()
    #expect(controller.script.model.preferredSpeedLinesPerMinute == changed)
    #expect(controller.state.speed == changed)
    #expect(controller.session.preferredLPM == changed)
  }

  @Test func styleUndoAndRedoSynchronizeThePausedTake() async throws {
    let controller = try await prepared(20)
    defer { controller.close() }
    let undo = try #require(controller.editor.undoManager)
    undo.removeAllActions()
    let original = controller.script.model.readingStyle
    var changed = original
    changed.fontSize += 10

    controller.changeStyle(changed)
    await settle(controller)
    #expect(controller.session.state == .paused)
    #expect(controller.session.style == changed)

    undo.undo()
    await settle(controller)
    #expect(controller.script.model.readingStyle == original)
    #expect(controller.state.style == original)
    #expect(controller.session.style == original)

    undo.redo()
    await settle(controller)
    #expect(controller.script.model.readingStyle == changed)
    #expect(controller.state.style == changed)
    #expect(controller.session.style == changed)
  }

  @Test func failedPreparationReleasesPresentationOwnership() {
    let unavailable = ScriptDocument()
    unavailable.source = NSAttributedString(string: "Not downloaded yet")
    unavailable.cloudStatus = .notDownloaded
    let first = OperatorWindowController(document: unavailable)
    defer {
      first.stop()
      first.close()
    }

    first.toggle()
    #expect(first.session.state == .idle)
    #expect(PresentationCoordinator.shared.owner !== first)

    let second = OperatorWindowController(document: ScriptDocument())
    defer {
      second.stop()
      second.close()
    }
    second.script.source = NSAttributedString(string: "Available locally")
    second.toggle()
    #expect(PresentationCoordinator.shared.owner === second)
    #expect(second.session.state != .idle)
  }
}
