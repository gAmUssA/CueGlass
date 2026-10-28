import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@Suite(.serialized) @MainActor struct IntegrationTests {
  init() { _ = NSApplication.shared }
  let root = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["CUEFLOW_TEST_ROOT"]
      ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".build/test-fixtures").path, isDirectory: true)
  func cleanup(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch let error as NSError {
      Issue.record("Fixture cleanup failed: \(error.code)")
    }
  }
  func expectCueGlassDomain(_ body: () throws -> Void) {
    do {
      try body()
      Issue.record("expected a CueGlass error")
    } catch let error as NSError {
      #expect(error.domain == "CueGlass")
    }
  }
  func fixture(_ name: String, _ data: Data) throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }
  @Test func importsLeaveOriginalsUnchanged() throws {
    let original = "Привет 👩‍💻 é שלום\n\nEnd"
    let txt = try fixture("unicode.txt", Data(original.utf8))
    defer { cleanup(txt) }
    let before = try txt.resourceValues(forKeys: [.contentModificationDateKey])
    let imported = try ScriptImporter.read(txt)
    #expect(imported.attributed.string == original)
    let rtfData = try imported.attributed.data(
      from: NSRange(location: 0, length: imported.attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let rtf = try fixture("rich.rtf", rtfData)
    defer { cleanup(rtf) }
    #expect(try ScriptImporter.read(rtf).attributed.string == original)
    let controller = CueFlowDocumentController()
    let doc = try #require(
      controller.makeDocument(withContentsOf: txt, ofType: "public.plain-text") as? ScriptDocument)
    #expect(doc.fileURL == nil)
    #expect(doc.source.string == original)
    let reopened = ScriptDocument()
    try reopened.read(
      from: doc.data(ofType: ScriptDocument.nativeType), ofType: ScriptDocument.nativeType)
    #expect(reopened.source.string == original)
    #expect(reopened.model.documentID == doc.model.documentID)
    #expect(try Data(contentsOf: txt) == Data(original.utf8))
    #expect(
      try txt.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        == before.contentModificationDate)
    #expect(try Data(contentsOf: rtf) == rtfData)
  }
  @Test func rejectsForeignRTFAndBadDocuments() throws {
    #expect(throws: ImportError.invalidRTF) {
      try ScriptImporter.decodeRTF(Data("<html><a href='https://example.org'>bad</a></html>".utf8))
    }
    let doc = ScriptDocument()
    let previous = doc.source
    #expect(throws: (any Error).self) {
      try doc.read(from: Data("not JSON".utf8), ofType: ScriptDocument.nativeType)
    }
    #expect(doc.source == previous)
    let url = try fixture("oversize.txt", Data(repeating: 65, count: 8 * 1024 * 1024 + 1))
    defer { cleanup(url) }
    #expect(throws: ImportError.tooLarge) { try ScriptImporter.read(url) }
    let future = try fixture("future.cueflow", Data("{\"formatVersion\":2}".utf8))
    defer { cleanup(future) }
    #expect(throws: ScriptFileError.futureVersion(2)) {
      try doc.read(from: Data(contentsOf: future), ofType: ScriptDocument.nativeType)
    }
    #expect(doc.source == previous)
    doc.fileURL = future
    #expect(doc.saveBlockedReason != nil)
    expectCueGlassDomain { try doc.checkAutosavingSafety() }
    expectCueGlassDomain {
      try doc.writeSafely(
        to: future, ofType: ScriptDocument.nativeType, for: .autosaveInPlaceOperation)
    }
    expectCueGlassDomain {
      try doc.writeSafely(to: future, ofType: ScriptDocument.nativeType, for: .saveToOperation)
    }
    let recovered = root.appendingPathComponent("recovery.cueflow")
    defer { cleanup(recovered) }
    try doc.writeSafely(to: recovered, ofType: ScriptDocument.nativeType, for: .saveToOperation)
    #expect(try ScriptFileCodec.decode(Data(contentsOf: recovered)).model.formatVersion == 1)
    #expect(try Data(contentsOf: future) == Data("{\"formatVersion\":2}".utf8))
  }
  @Test func immutableTakeAndStall() throws {
    let doc = ScriptDocument()
    let session = PlaybackSession()
    var time = 0.0
    session.clock = { time }
    try session.toggle(doc)
    let expectedPosition = session.timeline.velocity * 0.2
    let id = session.snapshot?.id
    let text = session.snapshot?.attributed.string
    try session.noteFrame(target: 0.2, end: nil)
    doc.replaceSource(NSAttributedString(string: "New text"))
    session.changed(doc)
    #expect(session.pendingRevision)
    #expect(session.snapshot?.id == id)
    #expect(session.snapshot?.attributed.string == text)
    #expect(throws: (any Error).self) { try session.loadLatest(doc) }
    try session.noteFrame(target: 0.8, end: nil)
    #expect(session.state == .paused)
    #expect(try session.position(at: 0.8) == expectedPosition)
    time = 30
    try session.toggle(doc)
    #expect(session.snapshot?.id == id)
    #expect(try session.position(at: 30) == expectedPosition)
    try session.pause()
    try session.loadLatest(doc)
    #expect(session.snapshot?.attributed.string == "New text")
    #expect(session.snapshot?.id != id)
    #expect(try session.position(at: 30) == 0)
  }
  @Test func derivedStyleAndAnchorPreserveSource() throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (1...80).map { "Line \($0) alpha beta gamma delta" }.joined(separator: "\n"),
      attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    let before = try doc.data(ofType: ScriptDocument.nativeType)
    let snap = ScriptSnapshot(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      documentID: doc.model.documentID, revision: 0, attributed: doc.source)
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let viewport = PrompterViewport(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
    window.contentView = viewport
    var style = ReadingStyle()
    viewport.configure(snapshot: snap, style: style, size: CGSize(width: 1000, height: 700))
    viewport.apply(position: 700)
    let anchor = try #require(viewport.captureAnchor())
    #expect(anchor.utf16Offset > 0)
    style.fontSize = 90
    style.columnWidthFraction = 0.5
    viewport.configure(snapshot: snap, style: style, size: CGSize(width: 1200, height: 700))
    viewport.apply(position: try #require(viewport.restore(anchor)))
    let restored = try #require(viewport.captureAnchor())
    #expect(restored.utf16Offset == anchor.utf16Offset)
    #expect(try doc.data(ofType: ScriptDocument.nativeType) == before)
    let derived = PresentationBuilder.build(doc.source, style: style)
    #expect(derived.string == doc.source.string)
    #expect(
      (derived.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map {
        NSFontManager.shared.traits(of: $0).contains(.boldFontMask)
      } == true)
    window.contentView = nil
    window.close()
  }
  @Test func displayLinkTeardownAndFocus() throws {
    let doc = ScriptDocument()
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.toggle(doc)
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let viewport = PrompterViewport(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    window.contentView = viewport
    var driver: DisplayLinkDriver? = DisplayLinkDriver(viewport: viewport, session: session)
    weak let weakDriver = driver
    driver?.update()
    driver?.stop()
    driver = nil
    #expect(weakDriver == nil)
    #expect(!OperatorWindow.acceptsTransport(NSTextView()))
    #expect(!OperatorWindow.acceptsTransport(NSSlider()))
    #expect(OperatorWindow.acceptsTransport(viewport))
    window.contentView = nil
    window.close()
  }
  @Test func operatorRendersAndRoutesEditing() throws {
    let doc = ScriptDocument()
    doc.makeWindowControllers()
    let controller = try #require(doc.windowControllers.first as? OperatorWindowController)
    let window = try #require(controller.window)
    window.makeKeyAndOrderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(controller.preview.reflection.viewport.text.string.contains("Welcome to CueGlass"))
    let view = try #require(window.contentView)
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(
      to: root.deletingLastPathComponent().appendingPathComponent("operator-window.png"))
    window.makeFirstResponder(controller.editor)
    controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
    let space = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    window.sendEvent(space)
    let right = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil,
        characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
        charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!),
        isARepeat: false, keyCode: 124))
    window.sendEvent(right)
    #expect(controller.editor.string.hasPrefix(" "))
    #expect(controller.session.state == .idle)
    controller.session.clock = { 10 }
    controller.state.countdown = 0
    controller.toggle()
    #expect(controller.session.state == .running)
    #expect(!controller.editor.isEditable)
    let second = OperatorWindowController(document: ScriptDocument())
    #expect(throws: (any Error).self) { try PresentationCoordinator.shared.claim(second) }
    #expect(controller.session.state == .paused)
    controller.stop()
    #expect(controller.editor.isEditable)
    second.close()
    controller.close()
  }
  @Test func outputLossRetainsLastPresentedPosition() throws {
    let display = try #require(DisplayDescriptor.all().first)
    let doc = ScriptDocument()
    let controller = OperatorWindowController(document: doc)
    controller.session.clock = { 0 }
    try controller.session.prepare(doc)
    let output = OutputWindowController(display: display)
    #expect(output.window?.frame == display.screen.frame)
    controller.output = output
    output.onClose = { [weak controller] in controller?.outputClosed() }
    controller.session.logicalSize = display.screen.frame.size
    controller.render()
    try controller.session.toggle(doc)
    let expectedPosition = controller.session.timeline.velocity * 0.2
    try controller.session.noteFrame(target: 0.2, end: nil)
    controller.handleAvailableDisplayIDs([])
    #expect(controller.output == nil)
    #expect(controller.session.state == .paused)
    #expect(try controller.session.position(at: 30) == expectedPosition)
    controller.close()
  }
  @Test func richDiagnosticsAndNativeUndo() throws {
    let rich = NSMutableAttributedString(
      string: "Bold link", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    rich.addAttribute(
      .link, value: URL(string: "https://example.org")!, range: NSRange(location: 5, length: 4))
    let bytes = try rich.data(
      from: NSRange(location: 0, length: rich.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let imported = try ScriptImporter.decodeRTF(bytes)
    #expect(imported.attributed.string == "Bold link")
    #expect(!imported.warnings.isEmpty)
    let derived = PresentationBuilder.build(imported.attributed, style: ReadingStyle())
    #expect(derived.attribute(.link, at: 5, effectiveRange: nil) == nil)
    #expect(imported.attributed.attribute(.link, at: 5, effectiveRange: nil) != nil)
    let doc = ScriptDocument()
    let initial = doc.source.string
    doc.replaceSource(rich)
    doc.undoManager?.undo()
    #expect(doc.source.string == initial)
  }
  @Test func longScriptLayoutIsNotAnEstimatedEnd() throws {
    let source = NSAttributedString(
      string: (0..<10000).map { "Line \($0): one two three four five six seven eight nine" }.joined(
        separator: "\n"))
    let snap = ScriptSnapshot(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      documentID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, revision: 0,
      attributed: source)
    let viewport = PrompterViewport(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    viewport.configure(
      snapshot: snap, style: ReadingStyle(), size: CGSize(width: 1280, height: 720))
    #expect(viewport.endPosition == nil)
    viewport.apply(position: 1000.125)
    #expect(viewport.currentPosition == 1000.125)
    #expect(viewport.endPosition == nil)
  }
  @Test func nativeDiskSaveAndDefinitiveEnd() throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: "One short line", attributes: [.font: NSFont.systemFont(ofSize: 18)])
    let url = root.appendingPathComponent("saved.cueflow")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { cleanup(url) }
    try doc.writeSafely(to: url, ofType: ScriptDocument.nativeType, for: .saveOperation)
    let reopened = ScriptDocument()
    try reopened.read(from: url, ofType: ScriptDocument.nativeType)
    #expect(reopened.source.string == "One short line")
    let snapshot = ScriptSnapshot(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      documentID: doc.model.documentID, revision: 0, attributed: doc.source)
    let viewport = PrompterViewport(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    viewport.configure(
      snapshot: snapshot, style: ReadingStyle(), size: CGSize(width: 1280, height: 720))
    let end = try #require(viewport.endPosition)
    #expect(end > 0)
    #expect(end < 720)
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.toggle(doc)
    for step in 1...100 {
      try session.noteFrame(target: Double(step) / 10, end: end)
      if session.state == .paused { break }
    }
    #expect(session.state == .paused)
    #expect(session.message.contains("End of script"))
    #expect(try session.position(at: 30) == end)
  }
  @Test func localCloudAndSingleSession() async throws {
    #expect(try await DocumentStorageService.shared.container(identifier: "") == nil)
    let url = try fixture("local.txt", Data("local".utf8))
    defer { cleanup(url) }
    #expect(try await CloudStatus.map(DocumentStorageService.shared.metadata(url)) == .local)
  }
}

extension IntegrationTests {
  @Test func darkEditorRenderingPreservesAuthoredRTFAndUndo() throws {
    let rtf = Data(
      #"{\rtf1\ansi{\colortbl;\red0\green0\blue0;\red10\green10\blue10;\red200\green40\blue30;}\cf1 Black\par\cf2 Near black\par\cf3 Red}"#
        .utf8)
    let doc = ScriptDocument()
    doc.model.content.data = rtf
    doc.source = try ScriptImporter.decodeRTF(rtf).attributed
    let source = doc.source.copy() as! NSAttributedString
    let before = try ScriptFileCodec.decode(doc.data(ofType: ScriptDocument.nativeType)).model
      .content.data
    let controller = OperatorWindowController(document: doc)
    defer { controller.close() }
    let editor = controller.editor
    let manager = try #require(editor.textLayoutManager)
    let content = try #require(manager.textContentManager)
    let undo = try #require(editor.undoManager)
    undo.removeAllActions()
    undo.registerUndo(withTarget: doc) { $0.notice = "Undo sentinel" }
    undo.setActionName("Sentinel")
    let action = undo.undoActionName
    // Draws the editor through NSView's normal display path and returns, per
    // paragraph fragment, the brightest sRGB luminance inside its first 120 pt.
    func renderedLuminance() throws -> [CGFloat] {
      let rep = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
      editor.cacheDisplay(in: editor.bounds, to: rep)
      let scale = CGFloat(rep.pixelsWide) / editor.bounds.width
      var result: [CGFloat] = []
      manager.enumerateTextLayoutFragments(
        from: content.documentRange.location, options: [.ensuresLayout]
      ) { fragment in
        let frame = fragment.layoutFragmentFrame.offsetBy(
          dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        var brightest: CGFloat = 0
        for y in stride(from: frame.minY + 2, to: frame.maxY - 2, by: 1) {
          for x in stride(from: frame.minX + 1, to: min(frame.maxX, frame.minX + 120), by: 1) {
            if let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) {
              brightest = max(
                brightest,
                0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent)
            }
          }
        }
        result.append(brightest)
        return true
      }
      return result
    }
    func renderingColor(at offset: Int) -> NSColor? {
      var color: NSColor?
      manager.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) {
        _, attributes, range in
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        if start <= offset, offset < end { color = attributes[.foregroundColor] as? NSColor }
        return color == nil
      }
      return color
    }
    #expect(editor.isFlipped)
    editor.appearance = NSAppearance(named: .darkAqua)
    let dark = try renderedLuminance()
    #expect(dark.count == 3)
    #expect(dark.prefix(2).allSatisfy { $0 > 0.6 })
    #expect(renderingColor(at: 0) == NSColor.labelColor)
    #expect(renderingColor(at: 6) == NSColor.labelColor)
    #expect(renderingColor(at: 17) == nil)
    #expect(editor.attributedString() == source)
    #expect(doc.source == source)
    #expect(doc.model.content.data == rtf)
    #expect(
      try ScriptFileCodec.decode(doc.data(ofType: ScriptDocument.nativeType)).model.content.data
        == before)
    #expect(undo.canUndo && !undo.canRedo && undo.undoActionName == action)
    editor.appearance = NSAppearance(named: .aqua)
    #expect(renderingColor(at: 0) == nil)
    _ = try renderedLuminance()
    editor.appearance = NSAppearance(named: .darkAqua)
    #expect(try renderedLuminance().prefix(2).allSatisfy { $0 > 0.6 })
    #expect(renderingColor(at: 0) == NSColor.labelColor)
    #expect(editor.attributedString() == source)
    #expect(doc.source == source)
    #expect(
      try ScriptFileCodec.decode(doc.data(ofType: ScriptDocument.nativeType)).model.content.data
        == before)
    #expect(undo.undoActionName == action)
    undo.undo()
    #expect(doc.notice == "Undo sentinel")
    #expect(!undo.canUndo)
  }
}
