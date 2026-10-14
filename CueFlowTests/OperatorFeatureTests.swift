import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

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
  private func prepared(_ paragraphs: Int = 200) async throws -> OperatorWindowController {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<paragraphs).map { "Paragraph \($0) alpha beta gamma delta epsilon" }.joined(
        separator: "\n"))
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

    c.state.selectedDisplay = oldDisplay.selectionKey
    c.refreshScreens([oldDisplay])
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
    let theme = try #require(content.superview)
    // An occluder paints after the target's owner in view order, belongs to
    // neither the owner's subtree, its ancestors nor the owner's own split
    // column, and overlaps the target. Targets exclude the 4 pt divider hit slop.
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
        let overlap = rect.intersection(target.insetBy(dx: 4, dy: 0))
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
