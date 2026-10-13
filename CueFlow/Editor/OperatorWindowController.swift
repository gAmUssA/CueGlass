import AppKit
import CueFlowCore
import SwiftUI

@MainActor final class OperatorState: ObservableObject {
  @Published var status = "Ready"
  @Published var cloud = "iCloud not configured in this build"
  @Published var speed = 40.0
  @Published var style = ReadingStyle()
  @Published var horizontal = UserDefaults.standard.bool(forKey: "reflectHorizontal")
  @Published var vertical = UserDefaults.standard.bool(forKey: "reflectVertical")
  @Published var calibrated = false
  @Published var selectedDisplay = ""
  @Published var displays: [String] = []
  @Published var active = false
  @Published var running = false
  @Published var pending = false
}
@MainActor final class OperatorWindow: NSWindow {
  weak var controller: OperatorWindowController?
  static func acceptsTransport(_ responder: NSResponder?) -> Bool {
    var current = responder
    while let candidate = current {
      if candidate is NSText || candidate is NSControl
        || candidate is NSHostingView<OperatorControls>
      {
        return false
      }
      current = candidate.nextResponder
    }
    return true
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53, controller?.output != nil {
      controller?.hideOutput()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
      Self.acceptsTransport(firstResponder)
    {
      switch event.keyCode {
      case 49:
        controller?.toggle()
        return
      case 126:
        controller?.adjustSpeed(5)
        return
      case 125:
        controller?.adjustSpeed(-5)
        return
      case 53:
        controller?.hideOutput()
        return
      default: break
      }
    }
    super.keyDown(with: event)
  }
}
@MainActor final class DropEditor: NSTextView {
  var onDrop: ((URL) -> Void)?
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    sender.draggingPasteboard.canReadObject(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      ? .copy : super.draggingEntered(sender)
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      let url = urls.first
    {
      onDrop?(url)
      return true
    }
    return super.performDragOperation(sender)
  }
}
@MainActor
final class OperatorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
  let script: ScriptDocument
  let state = OperatorState()
  let session = PlaybackSession()
  let editor = DropEditor(usingTextLayoutManager: true)
  let preview = ScaledPreviewContainer(frame: .zero)
  var output: OutputWindowController?
  private var replacingEditor = false
  private var sample: ScriptSnapshot?
  init(document: ScriptDocument) {
    script = document
    let window = OperatorWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1160, height: 850),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init(window: window)
    window.controller = self
    window.delegate = self
    window.title = "CueFlow"
    window.minSize = NSSize(width: 950, height: 700)
    window.setFrameAutosaveName("CueFlowOperator")
    state.style = script.model.readingStyle
    state.speed = script.model.preferredSpeedPointsPerSecond
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = editor
    editor.isRichText = true
    editor.allowsUndo = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainerInset = NSSize(width: 12, height: 12)
    editor.delegate = self
    editor.registerForDraggedTypes([.fileURL])
    editor.onDrop = { [weak self] url in self?.openDrop(url) }
    editor.setAccessibilityLabel("Script editor")
    editor.textStorage?.setAttributedString(script.source)
    let controls = NSHostingView(rootView: OperatorControls(state: state, controller: self))
    let split = NSSplitView()
    split.isVertical = true
    split.dividerStyle = .thin
    split.addArrangedSubview(scroll)
    split.addArrangedSubview(preview)
    window.contentView = root
    for child in [controls, split] {
      child.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(child)
    }
    NSLayoutConstraint.activate([
      controls.topAnchor.constraint(equalTo: root.topAnchor),
      controls.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      controls.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      controls.heightAnchor.constraint(equalToConstant: 310),
      split.topAnchor.constraint(equalTo: controls.bottomAnchor),
      split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
      preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 350),
    ])
    split.setPosition(480, ofDividerAt: 0)
    preview.reflection.viewport.driver = DisplayLinkDriver(
      viewport: preview.reflection.viewport, session: session)
    preview.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
    session.onChange = { [weak self] in self?.refresh() }
    NotificationCenter.default.addObserver(
      self, selector: #selector(documentChanged), name: ScriptDocument.replaced, object: script)
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(accountChanged), name: .NSUbiquityIdentityDidChange, object: nil)
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
      NSWorkspace.shared.notificationCenter.addObserver(
        self, selector: #selector(sleeping), name: name, object: nil)
    }
    refreshScreens()
    render()
    refresh()
    Task { await script.refreshCloudStatus() }
  }
  required init?(coder: NSCoder) { fatalError("Use init(document:)") }
  func present(_ error: Error) { script.presentError(error) }
  func perform(_ work: () throws -> Void) {
    do { try work() } catch let error as NSError { present(error) }
  }
  func toggle() {
    perform {
      try PresentationCoordinator.shared.claim(self)
      let wasIdle = session.state == .idle
      try session.toggle(script)
      if wasIdle { render() }
      refresh()
    }
  }
  func stop() {
    output?.close()
    output = nil
    session.stop()
    PresentationCoordinator.shared.release(self)
    render()
    refresh()
  }
  func restart() {
    perform {
      try session.pause()
      try session.seek(0)
      applyCurrentPosition()
    }
  }
  func adjustSpeed(_ delta: Double) { setSpeed(min(300, max(1, state.speed + delta))) }
  func setSpeed(_ value: Double) {
    perform {
      try session.speed(value)
      state.speed = value
      let previous = script.model.preferredSpeedPointsPerSecond
      script.undoManager?.registerUndo(withTarget: script) { doc in
        doc.model.preferredSpeedPointsPerSecond = previous
        doc.updateChangeCount(.changeDone)
      }
      script.model.preferredSpeedPointsPerSecond = value
      script.updateChangeCount(.changeDone)
    }
  }
  func changeStyle(_ style: ReadingStyle) {
    perform {
      let style = try ScriptFileCodec.validatedStyle(style)
      try session.pause()
      let anchor = authoritative.captureAnchor()
      state.style = style
      session.style = style
      script.setStyle(style)
      render()
      if let anchor, let position = authoritative.restore(anchor) {
        try session.seek(position)
        applyCurrentPosition()
      }
      session.message = "Paused for layout change"
      refresh()
      if let name = style.fontIdentifier, NSFont(name: name, size: style.fontSize) == nil {
        state.status = "Font unavailable — using the system font"
      }
    }
  }
  var authoritative: PrompterViewport { output?.reflection.viewport ?? preview.reflection.viewport }
  func render() {
    let snapshot: ScriptSnapshot
    if let take = session.snapshot {
      snapshot = take
    } else {
      snapshot = ScriptSnapshot(
        id: UUID(), documentID: script.model.documentID, revision: script.revision,
        attributed: script.source.copy() as! NSAttributedString)
      sample = snapshot
    }
    let style = session.state == .idle ? state.style : session.style
    preview.logicalSize = session.logicalSize
    preview.reflection.viewport.configure(
      snapshot: snapshot, style: style, size: session.logicalSize)
    output?.reflection.viewport.configure(
      snapshot: snapshot, style: style, size: session.logicalSize)
    reflect()
    applyCurrentPosition()
  }
  func applyCurrentPosition() {
    perform {
      let p = try session.position(at: session.effectiveTime)
      preview.reflection.viewport.apply(position: p)
      output?.reflection.viewport.apply(position: p)
    }
  }
  func refresh() {
    state.active = session.state != .idle
    state.running = session.state == .running
    state.pending = session.pendingRevision
    editor.isEditable = !state.active
    state.status =
      session.message + (state.active ? " · Editing locked; Stop to edit." : "")
      + (script.notice.isEmpty ? "" : " · " + script.notice)
    state.cloud =
      containerID.isEmpty ? "iCloud not configured in this build" : script.cloudStatus.rawValue
    preview.reflection.viewport.driver?.authoritative = output == nil
    preview.reflection.viewport.driver?.update()
    output?.reflection.viewport.driver?.update()
  }
  func reflect() {
    if ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" {
      UserDefaults.standard.set(state.horizontal, forKey: "reflectHorizontal")
      UserDefaults.standard.set(state.vertical, forKey: "reflectVertical")
    }
    output?.reflection.horizontal = state.horizontal
    output?.reflection.vertical = state.vertical
    preview.reflection.horizontal = state.calibrated && state.horizontal
    preview.reflection.vertical = state.calibrated && state.vertical
  }
  func loadLatest() {
    perform {
      let oldText = session.snapshot?.attributed.string
      let anchor = authoritative.captureAnchor()
      try session.loadLatest(script)
      state.style = script.model.readingStyle
      render()
      if oldText == session.snapshot?.attributed.string, let anchor, let id = session.snapshot?.id {
        let updated = ReadingAnchor(
          snapshotID: id, utf16Offset: anchor.utf16Offset,
          intraLineFraction: anchor.intraLineFraction)
        if let position = authoritative.restore(updated) {
          try session.seek(position)
          applyCurrentPosition()
        }
      }
      refresh()
    }
  }
  func calibration() {
    guard session.state == .idle else {
      state.status = "Stop the take before loading calibration"
      return
    }
    script.replaceSource(
      NSAttributedString(
        string:
          "UP ↑\nLEFT ← 1. CueFlow → RIGHT\n2. Read this asymmetric line\n3. ABC 123 →\nDOWN ↓",
        attributes: [.font: NSFont.systemFont(ofSize: 18)]))
  }
  func showOutput() {
    if output != nil {
      hideOutput()
      return
    }
    let displays = DisplayDescriptor.all()
    guard
      let display = displays.first(where: {
        ($0.preference.uuid ?? $0.preference.name) == state.selectedDisplay
      })
    else {
      state.status = "Saved display not connected — choose a display"
      return
    }
    if display.screen == window?.screen {
      let alert = NSAlert()
      alert.messageText = "Present on the operator screen?"
      alert.informativeText =
        "Output will cover this screen. Press Escape or use Stop Output to return."
      alert.addButton(withTitle: "Present")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    perform {
      try PresentationCoordinator.shared.claim(self)
      try session.prepare(script)
      try session.pause()
      let anchor = authoritative.captureAnchor()
      session.logicalSize = display.screen.frame.size
      let next = OutputWindowController(display: display)
      output = next
      next.reflection.viewport.driver = DisplayLinkDriver(
        viewport: next.reflection.viewport, session: session)
      next.reflection.viewport.driver?.authoritative = true
      next.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
      next.onClose = { [weak self] in self?.outputClosed() }
      render()
      if let anchor, let position = authoritative.restore(anchor) {
        try session.seek(position)
        applyCurrentPosition()
      }
      next.showWindow(nil)
      next.window?.orderFrontRegardless()
      window?.makeKeyAndOrderFront(nil)
      UserDefaults.standard.set(
        try JSONEncoder().encode(display.preference), forKey: "displayPreference")
      refresh()
    }
  }
  func hideOutput() { output?.close() }
  func outputClosed() {
    perform { try session.pauseSafely("Output stopped — position retained") }
    output?.reflection.viewport.driver?.stop()
    output = nil
    refresh()
  }
  @objc func screensChanged() {
    handleAvailableDisplayIDs(DisplayDescriptor.all().map(\.id))
    refreshScreens()
  }
  func handleAvailableDisplayIDs(_ ids: [CGDirectDisplayID]) {
    if let output, !ids.contains(output.displayID) {
      perform { try session.pauseSafely("Output display disconnected — choose a display") }
      hideOutput()
      state.status = "Output display disconnected — choose a display"
    }
  }
  func refreshScreens() {
    let displays = DisplayDescriptor.all()
    state.displays = displays.map { $0.preference.uuid ?? $0.preference.name }
    if state.selectedDisplay.isEmpty,
      let data = UserDefaults.standard.data(forKey: "displayPreference")
    {
      do {
        let saved = try JSONDecoder().decode(DisplayPreference.self, from: data)
        if let i = DisplayMatcher.match(saved, in: displays.map(\.preference)) {
          state.selectedDisplay = state.displays[i]
        } else {
          state.status = "Saved display not connected"
          state.selectedDisplay = "disconnected"
        }
      } catch let error as NSError {
        state.status = "Display preference could not be read (\(error.code)). Choose a display."
      }
    }
    if state.selectedDisplay.isEmpty { state.selectedDisplay = state.displays.first ?? "" }
  }
  func displayName(_ key: String) -> String {
    guard
      let d = DisplayDescriptor.all().first(where: {
        ($0.preference.uuid ?? $0.preference.name) == key
      })
    else { return "Disconnected" }
    return d.preference.name + (d.screen == window?.screen ? " (operator screen)" : "")
  }
  @objc func sleeping() { perform { try session.pauseSafely("Paused for sleep") } }
  @objc func accountChanged() {
    script.notice =
      "iCloud account changed or unavailable. Unsaved edits are kept; use Save a Copy for local recovery."
    refresh()
    Task { await script.refreshCloudStatus() }
  }
  @objc func documentChanged() {
    session.changed(script)
    if !replacingEditor {
      replacingEditor = true
      let selected = editor.selectedRange()
      editor.textStorage?.setAttributedString(script.source)
      editor.setSelectedRange(
        NSRange(location: min(selected.location, editor.string.utf16.count), length: 0))
      replacingEditor = false
    }
    if session.state == .idle {
      state.style = script.model.readingStyle
      render()
    }
    refresh()
  }
  func textDidChange(_ notification: Notification) {
    guard !replacingEditor, session.state == .idle else { return }
    replacingEditor = true
    script.replaceSource(editor.attributedString(), registerUndo: false)
    replacingEditor = false
  }
  func openDrop(_ url: URL) {
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) {
      [weak self] _, _, error in if let error { self?.present(error) }
    }
  }
  var containerID: String {
    Bundle.main.object(forInfoDictionaryKey: "CueFlowICloudContainerIdentifier") as? String ?? ""
  }
  func saveICloud() {
    Task { [weak self] in
      guard let self else { return }
      let container: URL?
      do {
        container = try await DocumentStorageService.shared.container(identifier: containerID)
      } catch let error as NSError {
        present(error)
        return
      }
      guard let directory = container
      else {
        state.status =
          containerID.isEmpty
          ? "iCloud not configured. Use File → Save for On This Mac."
          : "iCloud unavailable. Unsaved edits are kept; save On This Mac."
        return
      }
      let panel = NSSavePanel()
      panel.directoryURL = directory
      panel.nameFieldStringValue = script.model.title + ".cueflow"
      guard panel.runModal() == .OK, let url = panel.url else { return }
      script.save(to: url, ofType: ScriptDocument.nativeType, for: .saveAsOperation) {
        [weak self] error in
        if let error { self?.present(error) }
        Task { await self?.script.refreshCloudStatus() }
      }
    }
  }
  func requestDownload() {
    guard let url = script.fileURL else { return }
    Task {
      do {
        try await DocumentStorageService.shared.download(url)
        state.cloud = "Downloading…"
        await script.refreshCloudStatus()
      } catch let error as NSError { present(error) }
    }
  }
  func windowWillClose(_ notification: Notification) {
    stop()
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }
}
