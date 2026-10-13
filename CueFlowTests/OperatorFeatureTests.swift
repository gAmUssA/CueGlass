import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@Suite(.serialized) @MainActor struct OperatorFeatureTests {
  init() { _ = NSApplication.shared }
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
    window.setContentSize(CGSize(width: 1280, height: 748))
    controller.inspectorItem?.isCollapsed = false
    controller.balancePanes()
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(abs((controller.editor.enclosingScrollView?.frame.width ?? 0) - 420) < 2)
    #expect(abs(controller.stageView.frame.width - 578) < 2)
    let ratio = controller.preview.bounds.width / controller.preview.bounds.height
    #expect(
      abs(ratio - controller.session.logicalSize.width / controller.session.logicalSize.height)
        < 0.001)
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
    window.setContentSize(CGSize(width: 1002, height: 748))
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
