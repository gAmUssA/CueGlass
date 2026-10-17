import AppKit
import CueFlowCore
import QuartzCore
import Speech
import SwiftUI

struct VoiceFollowPlatformCapability: Equatable {
  let majorVersion: Int
  let speechTranscriberAvailable: Bool

  var allowsVoiceFollow: Bool { majorVersion >= 26 && speechTranscriberAvailable }
}

@MainActor final class OperatorState: ObservableObject {
  @Published var status = "Ready"
  @Published var cloud = "iCloud not configured in this build"
  @Published var speed = 30.0
  @Published var maximum = 240.0
  @Published var fineStep = 1.0
  @Published var jumpStep = 10.0
  @Published var countdown = 0
  @Published var duration = 300.0
  @Published var hideControls = false
  @Published var floatingOpacity = 0.85
  @Published var clickThrough = false
  @Published var overFullScreen = true
  @Published var contrastWarning = ""
  @Published var style = ReadingStyle()
  @Published var horizontal = UserDefaults.standard.bool(forKey: "reflectHorizontal")
  @Published var vertical = UserDefaults.standard.bool(forKey: "reflectVertical")
  @Published var calibrated = false
  @Published var selectedDisplay = ""
  @Published var displays: [String] = []
  @Published var darkAppearance = false
  @Published var active = false
  @Published var running = false
  @Published var pending = false
  @Published var voiceAvailable = false
  @Published var voiceState: VoiceFollowUIState = .hidden
  @Published var voiceLocales: [VoiceLocaleOption] = []
  @Published var voiceLocale = ""
  @Published var voiceInputDevices: [VoiceInputDeviceOption] = []
  /// Selected microphone UID; empty follows the system default input.
  @Published var voiceInputDevice = ""
  @Published var voiceInputNotice = ""
  @Published var voiceActive = false
  @Published var voiceSuspended = false
  @Published var voiceMessage = ""
  @Published var cameraDockWidth = 360.0
  @Published var cameraDockLineCount = CameraDockGeometry.defaultLineCount
  @Published var cameraDockHorizontalNudge = 0.0
  @Published var cameraDockNotchIsland = true
  @Published var cameraDockReady = false
  @Published var cameraDockFirstUseCalloutVisible = false
  @Published var cameraDockPlacementPreviewExpanded = false
}

private enum CameraDockReturnSurface {
  case preview(CGSize, wasRunning: Bool)
  case floating(CGSize, wasRunning: Bool)
  case output(String, CGSize, wasRunning: Bool)

  var logicalSize: CGSize {
    switch self {
    case .preview(let size, _), .floating(let size, _), .output(_, let size, _): size
    }
  }

  var wasRunning: Bool {
    switch self {
    case .preview(_, let wasRunning), .floating(_, let wasRunning),
      .output(_, _, let wasRunning):
      wasRunning
    }
  }
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
    if event.modifierFlags.contains(.command),
      CommandRouter.route(event, window: self, controller: controller)
    {
      return true
    }
    if event.keyCode == 53, controller?.output != nil || controller?.floating != nil {
      controller?.hideOutput()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override func orderOut(_ sender: Any?) {
    if let controller, controller.output == nil, controller.floating == nil {
      controller.perform { try controller.session.pauseSafely("Local preview hidden — paused") }
    }
    super.orderOut(sender)
  }
  override func keyDown(with event: NSEvent) {
    if !CommandRouter.route(event, window: self, controller: controller) {
      super.keyDown(with: event)
    }
  }

}
@MainActor final class DropEditor: NSTextView {
  var onAppearanceChange: ((Bool) -> Void)?
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearanceRendering()
    onAppearanceChange?(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
  }
  /// Re-applies display-only colors to every stored run; TextKit 2 does not
  /// re-run the validator for fragments it has already laid out.
  func refreshAppearanceRendering() {
    guard let manager = textLayoutManager, let content = manager.textContentManager,
      let storage = textStorage
    else { return }
    let whole = content.documentRange
    manager.setRenderingAttributes([:], for: whole)
    if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      storage.enumerateAttribute(
        .foregroundColor, in: NSRange(location: 0, length: storage.length)
      ) { value, run, _ in
        var nearBlack = value == nil
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
          if let color = (value as? NSColor)?.usingColorSpace(.sRGB) {
            nearBlack = max(color.redComponent, color.greenComponent, color.blueComponent) <= 0.1
          }
        }
        guard nearBlack, let start = content.location(whole.location, offsetBy: run.location),
          let end = content.location(start, offsetBy: run.length),
          let range = NSTextRange(location: start, end: end)
        else { return }
        manager.setRenderingAttributes([.foregroundColor: NSColor.labelColor], for: range)
      }
    }
    needsDisplay = true
  }
  func installAppearanceRendering() {
    textLayoutManager?.renderingAttributesValidator = { [weak self] manager, fragment in
      guard let self, let storage = self.textStorage,
        let content = manager.textContentManager
      else { return }
      manager.setRenderingAttributes([:], for: fragment.rangeInElement)
      guard self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else {
        return
      }
      let start = content.offset(
        from: content.documentRange.location, to: fragment.rangeInElement.location)
      let end = content.offset(
        from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
      guard start >= 0, end <= storage.length, end > start else { return }
      storage.enumerateAttribute(
        .foregroundColor, in: NSRange(location: start, length: end - start)
      ) {
        value, run, _ in
        var nearBlack = value == nil
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
          if let color = (value as? NSColor)?.usingColorSpace(.sRGB) {
            nearBlack = max(color.redComponent, color.greenComponent, color.blueComponent) <= 0.1
          }
        }
        guard nearBlack,
          let location = content.location(content.documentRange.location, offsetBy: run.location),
          let endLocation = content.location(location, offsetBy: run.length),
          let range = NSTextRange(location: location, end: endLocation)
        else { return }
        manager.setRenderingAttributes([.foregroundColor: NSColor.labelColor], for: range)
      }
    }
  }
  var onDrop: ((URL) -> Void)?
  lazy var decoration: EditorDecoration = {
    let view = EditorDecoration()
    view.editor = self
    view.wantsLayer = true
    view.layer?.zPosition = 100
    addSubview(view)
    return view
  }()
  var showsTake = false { didSet { decoration.needsDisplay = true } }
  var currentTakeOffset: Int? { didSet { decoration.needsDisplay = true } }
  private var paragraphStarts: [Int] = []
  private var indexedText = ""
  override func layout() {
    super.layout()
    let inset = CGSize(width: max(32, (bounds.width - 680) / 2), height: 24)
    if textContainerInset != inset { textContainerInset = inset }
    decoration.frame = bounds
    decoration.needsDisplay = true
  }

  func drawDecorations(_ rect: NSRect) {
    if indexedText != string {
      indexedText = string
      paragraphStarts = ParagraphIndex.starts(in: string)
    }
    guard let manager = textLayoutManager, let content = manager.textContentManager else { return }
    let start =
      manager.textViewportLayoutController.viewportRange?.location ?? content.documentRange.location
    manager.enumerateTextLayoutFragments(from: start, options: []) { fragment in
      var frame = fragment.layoutFragmentFrame.offsetBy(
        dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
      if frame.minY > rect.maxY { return false }
      let offset = content.offset(
        from: content.documentRange.location, to: fragment.rangeInElement.location)
      guard let number = self.paragraphStarts.firstIndex(of: offset), frame.intersects(rect) else {
        return true
      }
      let next =
        number + 1 < self.paragraphStarts.count
        ? self.paragraphStarts[number + 1] : self.string.utf16.count
      let current =
        self.showsTake && self.currentTakeOffset.map { $0 >= offset && $0 < next } == true
      frame.origin.x = 28
      frame.size.width = min(688, self.bounds.width - 32)
      if current {
        NSColor.controlAccentColor.withAlphaComponent(
          NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.16 : 0.07
        ).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0, dy: -3), xRadius: 4, yRadius: 4).fill()
        NSColor.controlAccentColor.setFill()
        NSRect(x: 28, y: frame.minY, width: 2, height: frame.height).fill()
      }
      (String(number + 1) as NSString).draw(
        at: NSPoint(x: 8, y: frame.minY + 2),
        withAttributes: [
          .font: NSFont.monospacedDigitSystemFont(
            ofSize: 10, weight: current ? .semibold : .regular),
          .foregroundColor: current ? NSColor.labelColor : NSColor.tertiaryLabelColor,
        ])
      return true
    }
  }
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
final class OperatorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate,
  NSToolbarDelegate
{
  let script: ScriptDocument
  let state = OperatorState()
  let session = PlaybackSession()
  var voiceCoordinator: VoiceFollowCoordinator?
  let editor = DropEditor(usingTextLayoutManager: true)
  let preview = ScaledPreviewContainer(frame: .zero)
  var output: OutputWindowController?
  var floating: FloatingPrompterWindowController?
  var cameraDock: FloatingPrompterWindowController? {
    floating?.isCameraDock == true ? floating : nil
  }
  var panel: ControlPanelController?
  let readout = TakeReadout()
  let splitController = NSSplitViewController()
  var inspectorPopover: NSPopover?
  var inspectorItem: NSSplitViewItem?
  private var userCollapsedInspector = UserDefaults.standard.bool(forKey: "inspectorCollapsed")
  var editorWidthConstraint: NSLayoutConstraint?
  var inspectorWidthConstraint: NSLayoutConstraint?
  weak var playToolbarButton: NSButton?
  var previewAspectConstraint: NSLayoutConstraint?
  let previewCaption = NSTextField(labelWithString: "Output preview · Local 1280 × 720")
  lazy var editorBanner = NSHostingView(rootView: EditorTakeBanner(controller: self))
  var stageView = StudioSurface()
  var transportChrome = NSView()
  var takeBar: NSView?
  var progressTimer: Timer?
  private var displayPreferencesBySelectionKey: [String: DisplayPreference] = [:]
  private var disconnectedDisplayPreference: DisplayPreference?
  private var cameraDockPreferenceCatalog = CameraDockPreferenceCatalog()
  private var cameraDockReturnSurface: CameraDockReturnSurface?
  private var cameraDockFirstUseAcknowledgedInProcess = false
  var displayProvider: () -> [DisplayDescriptor] = { DisplayDescriptor.all() }
  var pendingPlay: Bool {
    get { session.deferredStart == .play }
    set {
      if newValue {
        session.deferredStart = .play
      } else if pendingPlay {
        session.deferredStart = nil
      }
    }
  }
  var pendingResume: Bool {
    get { session.deferredStart == .resume }
    set {
      if newValue {
        session.deferredStart = .resume
      } else if pendingResume {
        session.deferredStart = nil
      }
    }
  }
  var pendingAnchor: ReadingAnchor?
  var pendingTimedDuration: Double?
  var renderGeneration = 0
  var lastPointerTime = CACurrentMediaTime()
  var lastPointer = NSEvent.mouseLocation

  private var replacingEditor = false
  private struct PendingVoiceRequest {
    let intent: VoiceStartIntent
    let resume: Bool
  }
  private var pendingVoiceRequest: PendingVoiceRequest?
  private var sample: ScriptSnapshot?
  private let voiceCapability: VoiceFollowPlatformCapability

  init(document: ScriptDocument, voiceCapabilityOverride: VoiceFollowPlatformCapability? = nil) {
    script = document
    voiceCapability = voiceCapabilityOverride ?? Self.currentVoiceCapability()
    let window = OperatorWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    super.init(window: window)
    window.controller = self
    window.delegate = self
    window.title = "CueGlass"
    window.subtitle = "On This Mac"
    window.minSize = CGSize(width: 980, height: 640)
    window.toolbarStyle = .unified
    state.style = script.model.readingStyle
    if let data = UserDefaults.standard.data(forKey: "cameraDockPreferences") {
      do {
        cameraDockPreferenceCatalog = try JSONDecoder().decode(
          CameraDockPreferenceCatalog.self, from: data)
      } catch {
        session.message =
          "Camera Dock settings could not be read (\(error)). Defaults will be used."
      }
    }
    state.speed = script.model.preferredSpeedLinesPerMinute
    if let value = UserDefaults.standard.object(forKey: "maximumLPM") as? Double {
      state.maximum = min(240, max(10, value))
    }
    session.configuredMax = state.maximum
    state.countdown = UserDefaults.standard.integer(forKey: "countdown")
    if ![0, 3, 5, 10].contains(state.countdown) { state.countdown = 0 }
    state.hideControls = UserDefaults.standard.bool(forKey: "hideControls")
    if let value = UserDefaults.standard.object(forKey: "floatingOpacity") as? Double {
      state.floatingOpacity = min(1, max(0.3, value))
    }
    state.clickThrough = UserDefaults.standard.bool(forKey: "clickThrough")
    if let v = UserDefaults.standard.object(forKey: "fineStep") as? Double, v.isFinite {
      state.fineStep = min(10, max(1, v))
    }
    if let v = UserDefaults.standard.object(forKey: "jumpStep") as? Double, v.isFinite {
      state.jumpStep = min(60, max(1, v))
    }
    if UserDefaults.standard.object(forKey: "overFullScreen") != nil {
      state.overFullScreen = UserDefaults.standard.bool(forKey: "overFullScreen")
    }
    editor.isRichText = true
    editor.allowsUndo = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.heightTracksTextView = false
    editor.onAppearanceChange = { [weak self] in self?.state.darkAppearance = $0 }
    editor.textContainerInset = CGSize(width: 32, height: 24)
    editor.delegate = self
    editor.font = .systemFont(ofSize: 15)
    let typingParagraph = NSMutableParagraphStyle()
    typingParagraph.minimumLineHeight = 22
    typingParagraph.maximumLineHeight = 22
    editor.typingAttributes = [
      .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor,
      .paragraphStyle: typingParagraph,
    ]
    editor.registerForDraggedTypes([.fileURL])
    editor.onDrop = { [weak self] in self?.openDrop($0) }
    editor.setAccessibilityLabel("Script editor")
    editor.textStorage?.setAttributedString(script.source)
    editor.installAppearanceRendering()
    let editorController = NSViewController()
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.documentView = editor
    // The locked-take notice sits over the page it locks (Quiet Studio ①/④), not in the stage.
    editorBanner.isHidden = true
    editorBanner.setContentHuggingPriority(.required, for: .vertical)
    editorBanner.setContentCompressionResistancePriority(.required, for: .vertical)
    // The banner never drives the pane's minimum width; it truncates instead.
    editorBanner.setContentCompressionResistancePriority(
      NSLayoutConstraint.Priority(1), for: .horizontal)
    let editorColumn = NSStackView(views: [editorBanner, scroll])
    editorColumn.orientation = .vertical
    editorColumn.spacing = 0
    editorColumn.alignment = .width
    editorColumn.translatesAutoresizingMaskIntoConstraints = false
    editorBanner.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      editorBanner.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
      editorBanner.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
    ])
    editorController.view = editorColumn
    let editorItem = NSSplitViewItem(viewController: editorController)
    editorItem.minimumThickness = 320
    editorItem.holdingPriority = NSLayoutConstraint.Priority(480)
    let stage = NSViewController()
    stage.view = stageView
    stageView.wantsLayer = true
    stageView.layer?.backgroundColor =
      NSColor(srgbRed: 0.086, green: 0.086, blue: 0.094, alpha: 1).cgColor
    let bar = NSHostingView(rootView: StageReadout(readout: readout))
    let footer = NSHostingView(rootView: StageFooter(state: state, controller: self))
    takeBar = bar
    bar.sizingOptions = []
    footer.sizingOptions = [.intrinsicContentSize]
    bar.appearance = NSAppearance(named: .darkAqua)
    footer.appearance = NSAppearance(named: .darkAqua)
    preview.wantsLayer = true
    preview.layer?.cornerRadius = 8
    preview.layer?.masksToBounds = true
    transportChrome = footer
    previewCaption.font = .systemFont(ofSize: 11, weight: .medium)
    // The caption truncates before it widens the stage.
    previewCaption.lineBreakMode = .byTruncatingTail
    previewCaption.maximumNumberOfLines = 1
    previewCaption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    previewCaption.textColor = .secondaryLabelColor
    previewCaption.appearance = NSAppearance(named: .darkAqua)
    let aspect = preview.heightAnchor.constraint(
      equalTo: preview.widthAnchor, multiplier: 9.0 / 16.0)
    previewAspectConstraint = aspect
    let preferredPreviewWidth = preview.widthAnchor.constraint(
      equalTo: stageView.widthAnchor, constant: -32)
    preferredPreviewWidth.priority = .defaultHigh
    for view in [bar, preview, previewCaption, footer] {
      view.translatesAutoresizingMaskIntoConstraints = false
      stageView.addSubview(view)
    }
    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: stageView.safeAreaLayoutGuide.topAnchor),
      bar.leadingAnchor.constraint(equalTo: stageView.leadingAnchor),
      // Keep the readout clear of the inspector split column's native divider,
      // which can extend several points into the stage on newer macOS releases.
      bar.trailingAnchor.constraint(equalTo: stageView.trailingAnchor, constant: -8),
      bar.heightAnchor.constraint(equalToConstant: 56),
      footer.leadingAnchor.constraint(equalTo: stageView.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: stageView.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: stageView.bottomAnchor),
      footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 82),
      preview.topAnchor.constraint(greaterThanOrEqualTo: bar.bottomAnchor, constant: 16),
      preview.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 16),
      aspect,
      previewCaption.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
      previewCaption.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
      previewCaption.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor),
      preferredPreviewWidth,
      preview.centerXAnchor.constraint(equalTo: stageView.centerXAnchor),
      preview.leadingAnchor.constraint(greaterThanOrEqualTo: stageView.leadingAnchor, constant: 16),
      preview.trailingAnchor.constraint(lessThanOrEqualTo: stageView.trailingAnchor, constant: -16),
      preview.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -32),
    ])
    let stageItem = NSSplitViewItem(viewController: stage)
    stageItem.minimumThickness = 420
    stageItem.holdingPriority = .defaultLow
    let inspector = NSViewController()
    inspector.view = NSView()
    let inspectorHost = NSHostingView(rootView: OperatorControls(state: state, controller: self))
    inspectorHost.sizingOptions = []
    inspectorHost.translatesAutoresizingMaskIntoConstraints = false
    inspector.view.addSubview(inspectorHost)
    NSLayoutConstraint.activate([
      inspectorHost.leadingAnchor.constraint(equalTo: inspector.view.leadingAnchor),
      inspectorHost.trailingAnchor.constraint(equalTo: inspector.view.trailingAnchor),
      inspectorHost.topAnchor.constraint(equalTo: inspector.view.safeAreaLayoutGuide.topAnchor),
      inspectorHost.bottomAnchor.constraint(equalTo: inspector.view.bottomAnchor),
    ])
    let item = NSSplitViewItem(inspectorWithViewController: inspector)
    item.minimumThickness = 260
    item.maximumThickness = 320
    let editorWidth = editorController.view.widthAnchor.constraint(equalToConstant: 420)
    editorWidth.priority = NSLayoutConstraint.Priority(490)
    editorWidth.isActive = true
    editorWidthConstraint = editorWidth
    let inspectorWidth = inspector.view.widthAnchor.constraint(equalToConstant: 280)
    inspectorWidth.priority = NSLayoutConstraint.Priority(490)
    inspectorWidth.isActive = true
    inspectorWidthConstraint = inspectorWidth
    item.collapseBehavior = .useConstraints
    item.canCollapse = true
    item.canCollapseFromWindowResize = true
    inspectorItem = item
    splitController.addSplitViewItem(editorItem)
    splitController.addSplitViewItem(stageItem)
    splitController.addSplitViewItem(item)
    window.contentViewController = splitController
    window.minSize = CGSize(width: 980, height: 640)
    item.isCollapsed = userCollapsedInspector
    let toolbar = NSToolbar(identifier: "CueGlassToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.centeredItemIdentifiers = [.init("transport")]
    window.toolbar = toolbar
    window.minSize = CGSize(width: 980, height: 640)
    window.setFrame(CGRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    window.contentView?.layoutSubtreeIfNeeded()
    balancePanes()
    preview.reflection.viewport.driver = DisplayLinkDriver(
      viewport: preview.reflection.viewport, session: session)
    preview.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
    session.onChange = { [weak self] in self?.refresh() }
    if #available(macOS 26.0, *), voiceCapability.allowsVoiceFollow {
      let coordinator = VoiceFollowCoordinator(
        session: session, source: SpeechVoiceSource(),
        usageDescription: {
          Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        })
      voiceCoordinator = coordinator
      state.voiceAvailable = true
      coordinator.onChange = { [weak self] in self?.syncVoiceState() }
      coordinator.onStopFollowing = { [weak self] in self?.stopVoiceFollow() }
      coordinator.onStopTake = { [weak self] in self?.stop() }
      Task { await coordinator.refreshAvailability() }
    }
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
    NotificationCenter.default.addObserver(
      self, selector: #selector(editorUndoChanged(_:)),
      name: Notification.Name.NSUndoManagerDidUndoChange, object: editor.undoManager)
    NotificationCenter.default.addObserver(
      self, selector: #selector(editorUndoChanged(_:)),
      name: Notification.Name.NSUndoManagerDidRedoChange, object: editor.undoManager)
    NotificationCenter.default.addObserver(
      self, selector: #selector(editorUndoGroupClosed(_:)),
      name: Notification.Name.NSUndoManagerDidCloseUndoGroup, object: editor.undoManager)
    CommandRouter.load()
    refreshScreens()
    refreshCameraDockPreferencesForTarget()
    render()
    refresh()
    Task { await script.refreshCloudStatus() }
  }
  required init?(coder: NSCoder) { fatalError("Use init(document:)") }

  private static func currentVoiceCapability() -> VoiceFollowPlatformCapability {
    let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    if #available(macOS 26.0, *) {
      return VoiceFollowPlatformCapability(
        majorVersion: majorVersion, speechTranscriberAvailable: SpeechTranscriber.isAvailable)
    }
    return VoiceFollowPlatformCapability(
      majorVersion: majorVersion, speechTranscriberAvailable: false)
  }

  func present(_ error: Error) { state.status = error.localizedDescription }
  func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { script.undoManager }
  func perform(_ work: () throws -> Void) {
    do { try work() } catch let error as NSError { present(error) }
  }
  func toggle() {
    if cameraDock != nil { state.cameraDockReady = false }
    if session.voiceSessionActive {
      if voiceCoordinator?.isCommandPaused == true {
        startVoiceFollow(resume: true)
      } else if session.voiceSuspended {
        startVoiceFollow(resume: true)
      } else {
        perform { try session.toggle(script) }
      }
      return
    }
    guard !script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      state.status = "Type, paste or drop a TXT or RTF script to begin."
      return
    }
    perform {
      try claimAndPrepare()
      if session.measuring {
        session.invalidateVoiceStartIntent("Play or Pause")
        pendingVoiceRequest = nil
        if pendingResume {
          pendingResume = false
          pendingPlay = false
        } else {
          pendingPlay.toggle()
        }
        state.status =
          pendingPlay
          ? "Measuring script… will start when ready" : "Measuring script… start cancelled"
        return
      }
      session.countdownSeconds = state.countdown
      try session.toggle(script)
      refresh()
    }
  }
  /// Manual takeover without a transport command: pauses a running take, cancels queued
  /// playback and any pending or spoken-paused Follow Voice activation, and closes its
  /// microphone. The position is kept; only an explicit Play or Resume starts again.
  func takeManualControl(_ reason: String) {
    pendingPlay = false
    pendingResume = false
    pendingVoiceRequest = nil
    state.cameraDockReady = false
    if session.state == .running || session.state == .countingDown {
      perform { try session.pause() }
    } else {
      session.suspendVoiceForManualControl(reason)
    }
    refresh()
  }
  func stop() {
    pendingVoiceRequest = nil
    voiceCoordinator?.stop()
    // Stop Take never revives the surface or play state the Dock replaced, but Preview
    // must come back at the logical size it had before the Dock, not the Dock strip's.
    cameraDockReturnSurface =
      cameraDock == nil
      ? nil
      : .preview(cameraDockReturnSurface?.logicalSize ?? session.logicalSize, wasRunning: false)
    hideOutput()
    panel?.close()
    panel = nil
    pendingPlay = false
    pendingResume = false
    pendingAnchor = nil
    state.cameraDockReady = false
    state.cameraDockFirstUseCalloutVisible = false
    pendingTimedDuration = nil
    session.measuring = false
    session.stop()
    PresentationCoordinator.shared.release(self)
    render()
    refresh()
  }
  func restart() {
    cancelPendingNavigation()
    perform {
      try session.restart()
      applyCurrentPosition()
      refresh()
    }
  }
  func adjustSpeed(_ delta: Double) { setSpeed(min(state.maximum, max(2, state.speed + delta))) }
  func setSpeed(_ value: Double) {
    perform {
      let cancelsPendingTimedScroll = pendingTimedDuration != nil
      let hasActiveTimedScroll = session.timedDuration != nil
      try session.speed(value)
      state.speed = session.preferredLPM
      pendingTimedDuration = nil
      if cancelsPendingTimedScroll && !hasActiveTimedScroll {
        session.message = "Timed Scrolling request canceled by manual pace change"
      }
      script.setPreferredSpeed(session.preferredLPM)
      refresh()
    }
  }
  func changeStyle(_ style: ReadingStyle) {
    perform {
      let style = try ScriptFileCodec.validatedStyle(style)
      let old = state.style
      let affectsLayout = styleAffectsLayout(from: old, to: style)
      if !affectsLayout {
        state.style = style
        session.style = style
        replacingEditor = true
        script.setStyle(style)
        replacingEditor = false
        updateAidsWithoutRelayout(style)
        refresh()
        return
      }
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = false
      state.style = style
      session.style = style
      replacingEditor = true
      script.setStyle(style)
      replacingEditor = false
      render()
      session.message = "Paused for layout change"
      refresh()
      if let name = style.fontIdentifier, NSFont(name: name, size: style.fontSize) == nil {
        state.status = "Font unavailable — using the system font"
      }
    }
  }
  /// Colour and guide edits recolour every live surface in place. The Dock decides whether
  /// its text panel shows from the background, so it refreshes that decision here too.
  private func updateAidsWithoutRelayout(_ style: ReadingStyle) {
    preview.reflection.viewport.updateAids(style)
    output?.reflection.viewport.updateAids(style)
    floating?.updateAids(style)
    updatePresentationBackground(style)
  }
  private func styleAffectsLayout(from old: ReadingStyle, to style: ReadingStyle) -> Bool {
    old.mode != style.mode || old.fontIdentifier != style.fontIdentifier
      || old.fontWeight != style.fontWeight || old.systemDesign != style.systemDesign
      || old.fontSize != style.fontSize || old.lineHeightMultiplier != style.lineHeightMultiplier
      || old.paragraphSpacing != style.paragraphSpacing
      || old.columnWidthFraction != style.columnWidthFraction
      || old.sideMarginFraction != style.sideMarginFraction
      || old.readingGuideFraction != style.readingGuideFraction
  }
  private func syncStyleAfterUndo() {
    let style = script.model.readingStyle
    let old = state.style
    guard old != style else { return }
    let affectsLayout = styleAffectsLayout(from: old, to: style)
    if affectsLayout, session.state != .idle {
      perform {
        try session.pause()
        preservePreparationAnchor()
        pendingPlay = false
        pendingResume = false
        state.style = style
        session.style = style
        script.notice = PresentationFont.notice(style) ?? ""
        render()
        session.message = "Paused for layout change"
        refresh()
      }
      return
    }
    state.style = style
    session.style = style
    if affectsLayout {
      render()
    } else {
      updateAidsWithoutRelayout(style)
    }
    script.notice = PresentationFont.notice(style) ?? ""
    refresh()
  }
  func enableTimedScrolling(seconds: Double) {
    perform {
      if session.state == .idle {
        try session.prepare(script)
        render()
      }
      if session.measuring {
        session.invalidateVoiceStartIntent("Timed Scrolling")
        pendingVoiceRequest = nil
        pendingTimedDuration = seconds
        session.message = "Measuring script… Timed Scrolling will be set when ready"
        refresh()
        return
      }
      try session.enableTimed(seconds: seconds)
      refresh()
    }
  }
  private func claimAndPrepare() throws {
    try PresentationCoordinator.shared.claim(self)
    do {
      if session.state == .idle {
        try session.prepare(script)
        render()
      }
    } catch {
      if session.state == .idle { PresentationCoordinator.shared.release(self) }
      throw error
    }
  }
  func startVoiceFollow(resume: Bool = false) {
    guard let coordinator = voiceCoordinator else { return }
    if resume, coordinator.isCommandPaused {
      coordinator.resumeSpokenCommandPause()
      return
    }
    guard !script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      state.status = "Type, paste or drop a TXT or RTF script to begin."
      return
    }
    do {
      try claimAndPrepare()
      if !session.voiceSessionActive,
        session.state == .running || session.state == .countingDown
      {
        try session.pause()
      }
    } catch {
      present(error)
      return
    }
    // Follow Voice supersedes actions queued during measurement; otherwise they are replayed
    // first when measurement completes and can invalidate the new voice-start intent.
    pendingPlay = false
    pendingResume = false
    pendingTimedDuration = nil
    guard let intent = session.beginVoiceStartIntent() else { return }
    let request = PendingVoiceRequest(intent: intent, resume: resume)
    if session.measuring {
      pendingVoiceRequest = request
      state.status = "Measuring script… Follow Voice will start when ready"
      return
    }
    beginVoiceFollow(coordinator, request: request)
  }
  private func beginVoiceFollow(
    _ coordinator: VoiceFollowCoordinator, request: PendingVoiceRequest
  ) {
    guard session.isCurrentVoiceStartIntent(request.intent),
      let snapshot = session.snapshot, let lineTable = authoritative.voiceLineTable
    else {
      state.status = "Text layout is not ready for Follow Voice"
      return
    }
    let index = ScriptIndex(text: snapshot.attributed.string)
    let initialOffset = authoritative.captureAnchor()?.utf16Offset ?? 0
    let resolveStart: @MainActor () -> Int? = { [weak self] in
      guard let self, self.session.isCurrentVoiceStartIntent(request.intent),
        self.session.snapshot?.id == snapshot.id
      else { return nil }
      let offset = self.authoritative.captureAnchor()?.utf16Offset ?? initialOffset
      return index.tokens.lastIndex { $0.range.lowerBound <= offset } ?? -1
    }
    guard resolveStart() != nil else { return }
    Task {
      if request.resume {
        await coordinator.resume(
          snapshot: snapshot, lineTable: lineTable, intent: request.intent,
          resolveStart: resolveStart)
      } else {
        await coordinator.start(
          snapshot: snapshot, lineTable: lineTable, intent: request.intent,
          resolveStart: resolveStart)
      }
    }
  }
  func installVoiceModel() {
    guard let coordinator = voiceCoordinator else { return }
    Task { await coordinator.installMissingModel() }
  }
  func cancelVoiceModelInstallation() { voiceCoordinator?.cancelInstallation() }
  func refreshVoiceAvailability() {
    guard let coordinator = voiceCoordinator else { return }
    Task { await coordinator.refreshAvailability() }
  }
  func stopVoiceFollow() {
    pendingVoiceRequest = nil
    voiceCoordinator?.stop()
  }
  func openMicrophoneSettings() { voiceCoordinator?.openMicrophoneSettings() }
  func selectVoiceLocale(_ identifier: String) { voiceCoordinator?.selectLocale(identifier) }
  func selectVoiceInputDevice(_ uid: String) {
    voiceCoordinator?.selectInputDevice(uid: uid.isEmpty ? nil : uid)
  }
  private func syncVoiceState() {
    guard let coordinator = voiceCoordinator else { return }
    state.voiceState = coordinator.state
    state.voiceLocales = coordinator.locales
    state.voiceLocale = coordinator.selectedLocaleIdentifier
    state.voiceInputDevices = coordinator.inputDevices
    state.voiceInputDevice = coordinator.selectedInputDeviceUID ?? ""
    state.voiceInputNotice = coordinator.inputRouteNotice ?? ""
    state.voiceActive = coordinator.isActive
    state.voiceSuspended = coordinator.isSuspended
    state.voiceMessage = voiceMessage(for: coordinator.state)
  }
  private func voiceMessage(for state: VoiceFollowUIState) -> String {
    switch state {
    case .hidden: ""
    case .checking: "Checking supported languages and the on-device speech model…"
    case .unavailable: "Speech transcription is unavailable on this Mac."
    case .unsupportedLocale: "The selected language is not supported on this Mac."
    case .needsModel: "The selected Apple speech model needs to be installed with your consent."
    case .downloading(let progress): "Installing speech model · \(Int(progress * 100))%"
    case .waitingForModel:
      "macOS is still downloading the speech model or waiting for network conditions. Check again shortly."
    case .ready:
      "English is the validated language. Other supported languages depend on macOS. Audio stays on this Mac and is not recorded."
    case .requestingMicrophone: "Waiting for microphone permission…"
    case .microphoneDenied:
      "Microphone access is off. Allow CueGlass in Privacy & Security → Microphone, then try again."
    case .starting: "Starting on-device speech analysis…"
    case .listening: "Listening · audio is not recorded"
    case .holding(let reason): reason
    case .commandPaused:
      "Paused · say ‘CueGlass, resume’ or ‘Prompter, resume’ · microphone active for commands"
    case .suspended(let reason): "Following paused · \(reason) · microphone closed"
    case .failed(let message): message
    }
  }
  var authoritative: PrompterViewport {
    output?.reflection.viewport ?? floating?.reflection.viewport ?? preview.reflection.viewport
  }
  private func updatePresentationBackground(_ style: ReadingStyle) {
    let color = PresentationBuilder.color(style.backgroundRGBA)
    preview.layer?.backgroundColor = color.cgColor
    output?.window?.backgroundColor = color
  }
  func render() {
    renderGeneration += 1
    let generation = renderGeneration
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
    if let cameraDock {
      if let size = cameraDock.updateCameraDockPresentation(style: style) {
        session.logicalSize = size
      } else {
        cameraDockPlacementUnavailable()
      }
    }
    preview.logicalSize = session.logicalSize
    updatePresentationBackground(style)
    let placementMap =
      cameraDock != nil || state.cameraDockPlacementPreviewExpanded
      ? cameraDockPlacementMap : nil
    preview.placementMapView.map = placementMap
    preview.placementMapView.isHidden = true
    if session.logicalSize.width > 0, session.logicalSize.height > 0 {
      previewAspectConstraint?.isActive = false
      previewAspectConstraint = preview.heightAnchor.constraint(
        equalTo: preview.widthAnchor,
        multiplier: session.logicalSize.height / session.logicalSize.width)
      previewAspectConstraint?.isActive = true
    }
    updatePreviewCaption()
    // While Camera Dock is active the editor preview mirrors the Dock's reading layout:
    // centred paragraphs, the wider column, and the reading line in the vertical centre.
    let dockLayout = cameraDock?.dockLayout
    preview.reflection.viewport.centersText = dockLayout != nil
    preview.reflection.viewport.columnWidthFractionOverride =
      dockLayout == nil ? nil : CameraDockGeometry.textColumnFraction
    preview.reflection.viewport.configure(
      snapshot: snapshot, style: style, size: session.logicalSize,
      guideFractionOverride: dockLayout?.guideFraction)
    output?.reflection.viewport.configure(
      snapshot: snapshot, style: style, size: session.logicalSize)
    floating?.root?.logicalSize = session.logicalSize
    floating?.reflection.viewport.configure(
      snapshot: snapshot, style: style, size: session.logicalSize,
      guideFractionOverride: dockLayout?.guideFraction,
      fadesTopEdge: cameraDock == nil)
    for (viewport, reflection) in [
      (preview.reflection.viewport, preview.reflection),
      (output?.reflection.viewport, output?.reflection),
      (floating?.reflection.viewport, floating?.reflection),
    ] {
      viewport?.onScrub = { [weak self, weak viewport, weak reflection] event in
        guard let self, let viewport else { return }
        let scale = viewport.convert(CGSize(width: 1, height: 1), to: nil).height
        self.scrub(
          delta: ScrubGate.delta(
            rawY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
            lineAdvance: self.session.lineAdvance, scale: abs(scale),
            verticalReflection: reflection?.vertical == true),
          momentum: !event.momentumPhase.isEmpty)
      }
    }
    reflect()
    preview.layoutSubtreeIfNeeded()
    applyCurrentPosition()
    if session.snapshot != nil {
      session.measuring = true
      // The first pass establishes the text view extent. The geometry query settles
      // its viewport before a second bounded pass records final fragment positions.
      let measured = authoritative
      measured.measure { [weak self] _, _, _, _ in
        guard let self, self.renderGeneration == generation else { return }
        guard measured === self.authoritative else { return self.render() }
        _ = measured.captureAnchor()
        measured.measure { [weak self] end, paragraphs, words, lines in
          guard let self, self.renderGeneration == generation else { return }
          guard measured === self.authoritative else { return self.render() }
          self.session.measuring = false
          self.perform {
            _ = self.authoritative.captureAnchor()
            let position = self.pendingAnchor.flatMap { self.authoritative.restore($0) }
            self.pendingAnchor = nil
            try self.session.updateLayout(
              end: end, paragraphs: paragraphs, wordCount: words, lineCount: lines,
              position: position)
            self.applyCurrentPosition()
          }
          if let seconds = self.pendingTimedDuration {
            self.pendingTimedDuration = nil
            self.perform { try self.session.enableTimed(seconds: seconds) }
          }
          if self.pendingResume {
            self.pendingResume = false
            self.resumeAfterMeasurement()
          } else if self.pendingPlay {
            self.pendingPlay = false
            self.toggle()
          }
          if let request = self.pendingVoiceRequest {
            self.pendingVoiceRequest = nil
            if self.session.isCurrentVoiceStartIntent(request.intent),
              let coordinator = self.voiceCoordinator
            {
              self.beginVoiceFollow(coordinator, request: request)
            }
          }
          self.refresh()
        }
      }
    }
  }
  func applyCurrentPosition() {
    perform {
      let p = try session.position(at: session.effectiveTime)
      preview.reflection.viewport.apply(position: p)
      output?.reflection.viewport.apply(position: p)
      floating?.reflection.viewport.apply(position: p)
    }
  }
  func refresh() {
    syncVoiceState()
    state.active = session.state != .idle
    state.running = session.state == .running || session.state == .countingDown
    state.pending = session.pendingRevision
    floating?.root?.updateCameraDockControls()
    editor.isEditable = !state.active
    editor.showsTake = state.active
    editorBanner.isHidden = !state.active
    editor.needsDisplay = true
    for button in [playToolbarButton, panel?.playButton].compactMap({ $0 }) {
      button.image = NSImage(
        systemSymbolName: session.state == .countingDown
          ? "xmark" : state.running ? "pause.fill" : "play.fill",
        accessibilityDescription: "Play or pause")
      button.toolTip =
        "Play / Pause · "
        + CommandRouter.map.bindings.filter { $0.command == .toggle }.map { $0.chord.label }.joined(
          separator: " · ")
    }
    refreshStatus()
    // The window subtitle is operator-facing: a local-only build is simply "On This Mac".
    state.cloud = containerID.isEmpty ? "On This Mac" : script.cloudStatus.rawValue
    preview.reflection.viewport.driver?.authoritative = output == nil && floating == nil
    preview.reflection.viewport.driver?.update()
    output?.reflection.viewport.driver?.update()
    floating?.reflection.viewport.driver?.update()
    floating?.window?.ignoresMouseEvents = state.clickThrough && session.state == .running
    state.speed = min(
      state.maximum,
      session.state == .idle ? script.model.preferredSpeedLinesPerMinute : session.preferredLPM)
    window?.subtitle = state.cloud
    if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "present" }) {
      let live = output != nil || cameraDock != nil || floating != nil
      item.label =
        output != nil
        ? "Presenting · \(output?.window?.screen?.localizedName ?? "Output")"
        : cameraDock != nil
          ? "Presenting · Camera Dock"
          : floating != nil ? "Presenting · Floating" : "Present"
      if let button = item.view as? NSPopUpButton {
        let menu = presentationMenu()
        let title = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        menu.insertItem(title, at: 0)
        button.menu = menu
        button.synchronizeTitleAndSelectedItem()
        // The output-mode chip takes the accent while live; the text carries the state too.
        button.contentTintColor = live ? .controlAccentColor : nil
      }
    }
    let toolbarButtons =
      window?.toolbar?.items.flatMap {
        ($0.view as? NSStackView)?.arrangedSubviews.compactMap { $0 as? ActionButton } ?? []
      } ?? []
    for button in toolbarButtons + (panel?.transportButtons ?? []) {
      if let command = button.playbackCommand {
        button.toolTip =
          command.rawValue + " · "
          + CommandRouter.map.bindings.filter { $0.command == command }.map { $0.chord.label }
          .joined(separator: " · ")
      }
    }
    updateReadout()
    updateEditorParagraph()
    updateProgressTimer()
    updateFloatingOptions()
  }
  private func refreshStatus() {
    state.status = session.message + (script.notice.isEmpty ? "" : " · " + script.notice)
    if let notice = PresentationFont.notice(state.style) { state.status += " · " + notice }
  }
  private func setPersistentStatus(_ message: String) {
    session.message = message
    refreshStatus()
  }
  func reflect() {
    if ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" {
      UserDefaults.standard.set(state.horizontal, forKey: "reflectHorizontal")
      UserDefaults.standard.set(state.vertical, forKey: "reflectVertical")
    }
    if floating?.isCameraDock == true {
      floating?.reflection.horizontal = false
      floating?.reflection.vertical = false
    } else {
      floating?.reflection.horizontal = state.horizontal
      floating?.reflection.vertical = state.vertical
    }
    output?.reflection.horizontal = state.horizontal
    output?.reflection.vertical = state.vertical
    // A calibrated preview shows what the live surface shows. Camera Dock never mirrors and
    // replaces the reading guide with its own emphasis, so the preview follows it.
    let dockLive = floating?.isCameraDock == true
    preview.reflection.horizontal = state.calibrated && state.horizontal && !dockLive
    preview.reflection.vertical = state.calibrated && state.vertical && !dockLive
    preview.reflection.viewport.hidesReadingGuide = state.calibrated && dockLive
    preview.reflection.viewport.updateReadingGuideVisibility()
    updatePreviewCaption()
  }

  private func updatePreviewCaption() {
    previewCaption.stringValue = Self.previewCaption(
      screen: output?.window?.screen?.localizedName ?? floating?.window?.screen?.localizedName,
      size: session.logicalSize,
      mirrored: preview.reflection.horizontal || preview.reflection.vertical)
  }
  /// The stage caption follows the Quiet Studio board: what the stage shows, which display,
  /// the exact logical size, and whether the operator sees it mirrored.
  static func previewCaption(screen: String?, size: CGSize, mirrored: Bool) -> String {
    "Output preview · \(screen ?? "Local") \(Int(size.width)) × \(Int(size.height))"
      + " · exact output layout, scaled · shown \(mirrored ? "mirrored" : "unmirrored")"
  }
  func loadLatest() {
    perform {
      let oldText = session.snapshot?.attributed.string
      // Load Latest is an explicit command: capture the current view, not an earlier intent.
      let anchor = authoritative.captureAnchor()
      try session.loadLatest(script)
      cancelPendingNavigation()
      pendingPlay = false
      pendingResume = false
      state.style = script.model.readingStyle
      if oldText == session.snapshot?.attributed.string, let anchor, let id = session.snapshot?.id {
        pendingAnchor = ReadingAnchor(
          snapshotID: id, utf16Offset: anchor.utf16Offset,
          intraLineFraction: anchor.intraLineFraction)
      }
      render()
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
          "UP ↑\nLEFT ← 1. CueGlass → RIGHT\n2. Read this asymmetric line\n3. ABC 123 →\nDOWN ↓",
        attributes: [.font: NSFont.systemFont(ofSize: 18)]))
  }
  func showOutput(confirm: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }) {
    if output != nil {
      hideOutput()
      return
    }
    let displays = displayProvider()
    guard
      let display = displays.first(where: {
        $0.selectionKey == state.selectedDisplay
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
      guard confirm(alert) == .alertFirstButtonReturn else { return }
    }
    perform {
      try claimAndPrepare()
      cameraDockReturnSurface = nil
      state.cameraDockReady = false
      state.cameraDockFirstUseCalloutVisible = false
      let wasRunning = !session.voiceSessionActive && (session.state == .running || pendingResume)
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = wasRunning
      floating?.onClose = nil
      floating?.close()
      floating = nil
      session.logicalSize = display.screen.frame.size
      let next = OutputWindowController(display: display)
      output = next
      (next.window as? OutputWindow)?.operatorController = self
      next.reflection.viewport.driver = DisplayLinkDriver(
        viewport: next.reflection.viewport, session: session)
      next.reflection.viewport.driver?.authoritative = true
      next.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
      next.onClose = { [weak self] in self?.outputClosed() }
      render()
      next.showWindow(nil)
      next.window?.orderFrontRegardless()
      window?.makeKeyAndOrderFront(nil)
      if ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" {
        UserDefaults.standard.set(
          try JSONEncoder().encode(display.preference), forKey: "displayPreference")
      }
      showControls()
      refresh()
    }
  }
  func hideOutput() {
    if let cameraDock {
      let destination =
        cameraDockReturnSurface ?? .preview(session.logicalSize, wasRunning: false)
      pendingAnchor = cameraDock.reflection.viewport.captureAnchor() ?? pendingAnchor
      cameraDockReturnSurface = nil
      cameraDock.onClose = nil
      cameraDock.close()
      floating = nil
      state.cameraDockReady = false
      state.cameraDockFirstUseCalloutVisible = false
      perform {
        try session.pause()
        preservePreparationAnchor()
        pendingPlay = false
        pendingResume = destination.wasRunning
      }
      switch destination {
      case .floating(_, _):
        showFloating()
      case .output(let displayKey, let size, _):
        // The return display was closed with Output when the Dock opened, so display loss
        // no longer tracked it. If it is gone, Preview takes the saved size and anchor.
        let message = "Output display disconnected — position retained"
        guard displayProvider().contains(where: { $0.selectionKey == displayKey }) else {
          pendingResume = false
          returnToPreview(size: size)
          setPersistentStatus(message)
          return
        }
        selectDisplay(displayKey)
        showOutput(confirm: { _ in .alertFirstButtonReturn })
        if output == nil {
          pendingResume = false
          returnToPreview(size: size)
          setPersistentStatus(message)
        }
      case .preview(let size, _):
        returnToPreview(size: size)
      }
      return
    }
    output?.close()
    floating?.close()
    floating = nil
    refresh()
  }
  private func returnToPreview(size: CGSize) {
    perform {
      let running = !session.voiceSessionActive && (session.state == .running || pendingResume)
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = running
      session.logicalSize = size
      render()
      refresh()
    }
  }
  func outputClosed() {
    perform { try session.pauseSafely("Output stopped — position retained") }
    output?.reflection.viewport.driver?.stop()
    output = nil
    refresh()
  }
  @objc func screensChanged() {
    handleScreenParametersChanged(displayProvider())
  }
  func handleScreenParametersChanged(_ displays: [DisplayDescriptor]) {
    let cameraDockWasDisconnected =
      cameraDock.map { dock in
        guard let id = dock.displayID else { return false }
        return !displays.contains { $0.id == id }
      } ?? false
    if let cameraDock, let displayUUID = cameraDock.displayUUID,
      let remapped = displays.first(where: {
        ($0.preference.uuid ?? $0.preference.name) == displayUUID
      })
    {
      cameraDock.displayID = remapped.id
    }
    handleAvailableDisplayIDs(displays.map(\.id))
    refreshScreens(displays)
    if cameraDockWasDisconnected {
      refreshStatus()
      render()
    }
    if let cameraDock,
      let display = displays.first(where: { $0.id == cameraDock.displayID }),
      !cameraDock.updateCameraDockPlacement(
        on: display, preferences: cameraDock.dockPreferences, style: session.style)
    {
      cameraDockPlacementUnavailable()
      render()
    }
  }
  func handleAvailableDisplayIDs(_ ids: [CGDirectDisplayID]) {
    if let cameraDock, let id = cameraDock.displayID, !ids.contains(id) {
      pendingAnchor = cameraDock.reflection.viewport.captureAnchor() ?? pendingAnchor
      let restoredSize = cameraDockReturnSurface?.logicalSize ?? session.logicalSize
      cameraDockReturnSurface = nil
      perform { try session.pauseSafely("Camera Dock display disconnected — position retained") }
      cameraDock.onClose = nil
      cameraDock.close()
      floating = nil
      session.logicalSize = restoredSize
      state.cameraDockReady = false
      state.cameraDockFirstUseCalloutVisible = false
      refresh()
      state.status = "Camera Dock display disconnected — position retained"
      return
    }
    if let floating, let id = floating.displayID, !ids.contains(id) {
      perform { try session.pauseSafely("Floating display disconnected — position retained") }
      if let screen = window?.screen ?? NSScreen.main, let frame = floating.window?.frame {
        floating.window?.setFrame(FrameClamp.clamp(frame, to: screen.visibleFrame), display: true)
        floating.displayID = DisplayDescriptor.all().first { $0.screen == screen }?.id
        floatingResized()
      }
    }
    if let output, !ids.contains(output.displayID) {
      perform { try session.pauseSafely("Output display disconnected — choose a display") }
      hideOutput()
      state.status = "Output display disconnected — choose a display"
    }
  }
  func refreshScreens(_ suppliedDisplays: [DisplayDescriptor]? = nil) {
    let displays = suppliedDisplays ?? displayProvider()
    let preferences = displays.map(\.preference)
    let selectedPreference =
      displayPreferencesBySelectionKey[state.selectedDisplay] ?? disconnectedDisplayPreference
    if let selectedPreference {
      if let index = DisplayMatcher.match(selectedPreference, in: preferences) {
        state.selectedDisplay = displays[index].selectionKey
        disconnectedDisplayPreference = nil
        if state.status == "Selected display not connected — choose a display"
          || state.status == "Saved display not connected"
        {
          refreshStatus()
        }
      } else {
        state.status = "Selected display not connected — choose a display"
        state.selectedDisplay = "disconnected"
        disconnectedDisplayPreference = selectedPreference
      }
    } else if state.selectedDisplay.isEmpty,
      let data = UserDefaults.standard.data(forKey: "displayPreference")
    {
      do {
        let saved = try JSONDecoder().decode(DisplayPreference.self, from: data)
        if let index = DisplayMatcher.match(saved, in: preferences) {
          state.selectedDisplay = displays[index].selectionKey
        } else {
          state.status = "Saved display not connected"
          state.selectedDisplay = "disconnected"
          disconnectedDisplayPreference = saved
        }
      } catch let error as NSError {
        state.status = "Display preference could not be read (\(error.code)). Choose a display."
      }
    }
    if state.selectedDisplay.isEmpty { state.selectedDisplay = displays.first?.selectionKey ?? "" }
    state.displays = displays.map(\.selectionKey)
    displayPreferencesBySelectionKey = Dictionary(
      uniqueKeysWithValues: displays.map { ($0.selectionKey, $0.preference) })
    refreshCameraDockPreferencesForTarget(displays: displays)
  }
  func displayName(_ key: String) -> String {
    guard
      let d = DisplayDescriptor.all().first(where: {
        $0.selectionKey == key
      })
    else { return "Disconnected" }
    return d.preference.name + (d.screen == window?.screen ? " (operator screen)" : "")
  }
  func windowDidMiniaturize(_ notification: Notification) {
    if output == nil && floating == nil {
      perform { try session.pauseSafely("Local preview hidden — paused") }
    }
  }
  @objc func sleeping() {
    perform { try session.pauseSafely("Paused for sleep") }
  }
  @objc func accountChanged() {
    script.notice =
      "iCloud account changed or unavailable. Unsaved edits are kept; use Save a Copy for local recovery."
    refresh()
    Task { await script.refreshCloudStatus() }
  }
  @objc func documentChanged() {
    session.changed(script)
    if !replacingEditor {
      let source = script.source
      if !editor.attributedString().isEqual(to: source) {
        replacingEditor = true
        let selected = editor.selectedRange()
        editor.textStorage?.setAttributedString(source)
        let textLength = editor.string.utf16.count
        let location = min(selected.location, textLength)
        let length = min(selected.length, textLength - location)
        editor.setSelectedRange(NSRange(location: location, length: length))
        replacingEditor = false
      }
    }
    if session.state == .idle && !replacingEditor {
      state.style = script.model.readingStyle
      session.style = script.model.readingStyle
      render()
    } else if !replacingEditor, session.snapshot?.revision == script.revision {
      syncStyleAfterUndo()
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
    progressTimer?.invalidate()
    progressTimer = nil
    stop()
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }
}

extension OperatorWindowController {
  func execute(_ command: PlaybackCommand) {
    lastPointerTime = session.clock()
    restoreChrome()
    switch command {
    case .toggle: toggle()
    case .faster: adjustSpeed(state.fineStep)
    case .slower: adjustSpeed(-state.fineStep)
    case .jumpFaster: adjustSpeed(state.jumpStep)
    case .jumpSlower: adjustSpeed(-state.jumpStep)
    case .restart: restart()
    case .nextParagraph:
      cancelPendingNavigation()
      perform {
        try session.step(forward: true)
        applyCurrentPosition()
      }
    case .previousParagraph:
      cancelPendingNavigation()
      perform {
        try session.step(forward: false)
        applyCurrentPosition()
      }
    case .reverse:
      cancelPendingNavigation()
      perform {
        pendingTimedDuration = nil
        try session.reverse()
        refresh()
      }
    case .exit: hideOutput()
    case .cameraDock: showCameraDock()
    }
  }
  func showControls() {
    if panel == nil { panel = ControlPanelController(controller: self) }
    panel?.placeSafely()
    refresh()
  }

  static let cameraDockExplainerSeenKey = "cameraDockExplainerSeen"
  static let cameraDockExplainer =
    "On notched displays, Camera Dock sits flush below the camera safe area and never covers the camera housing. On other displays, it sits below the visible menu bar and assumes the camera is there. The prompt may be visible in screen recordings and full-display shares. CueGlass does not access the camera or microphone for Camera Dock."
  static let cameraDockCaptureDisclosure =
    "The prompt may appear in screen recordings and full-display shares."

  var cameraDockMenuTitle: String {
    cameraDockMenuTitle(for: displayProvider())
  }

  var selectedPresentationSurface: String {
    if output != nil { return "output" }
    if cameraDock != nil { return "cameraDock" }
    if floating != nil { return "floating" }
    return "preview"
  }

  func selectPresentationSurface(_ surface: String) {
    switch surface {
    case "preview":
      if cameraDock != nil {
        let wasRunning = cameraDockReturnSurface?.wasRunning ?? false
        cameraDockReturnSurface = .preview(
          cameraDockReturnSurface?.logicalSize ?? session.logicalSize,
          wasRunning: wasRunning)
        hideOutput()
      } else if output != nil || floating != nil {
        hideOutput()
      }
    case "output": showOutput()
    case "floating": showFloating()
    case "cameraDock":
      if cameraDock == nil { showCameraDock() }
    default: break
    }
  }

  var cameraDockCameraMayBeElsewhere: Bool {
    guard let cameraDock, let displayID = cameraDock.displayID else { return false }
    let displays = displayProvider()
    guard let display = displays.first(where: { $0.id == displayID }) else { return false }
    return cameraMayBeElsewhere(on: display, among: displays)
  }

  private func cameraMayBeElsewhere(
    on display: DisplayDescriptor, among displays: [DisplayDescriptor]
  ) -> Bool {
    !display.isBuiltIn && displays.contains(where: \.isBuiltIn)
  }

  var cameraDockPlacementMap: CameraDockPlacementMap? {
    let displays = displayProvider()
    let display =
      cameraDock.flatMap { dock in
        displays.first(where: { $0.id == dock.displayID })
      } ?? cameraDockTarget(in: displays)
    guard let display else { return nil }
    let preferences = cameraDock?.dockPreferences ?? cameraDockPreferences(for: display)
    let style = session.state == .idle ? state.style : session.style
    guard
      let layout = FloatingPrompterWindowController.cameraDockLayout(
        display: display, preferences: preferences, style: style)
    else { return nil }
    return CameraDockGeometry.placementMap(
      for: layout, displayName: display.screen.localizedName,
      cameraMayBeElsewhere: cameraMayBeElsewhere(on: display, among: displays))
  }

  func setCameraDockPlacementPreviewExpanded(_ expanded: Bool) {
    guard state.cameraDockPlacementPreviewExpanded != expanded else { return }
    state.cameraDockPlacementPreviewExpanded = expanded
    render()
  }

  func acknowledgeCameraDockExplainer() {
    cameraDockFirstUseAcknowledgedInProcess = true
    state.cameraDockFirstUseCalloutVisible = false
    guard ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" else { return }
    UserDefaults.standard.set(true, forKey: Self.cameraDockExplainerSeenKey)
  }

  func showCameraDock() {
    guard cameraDock == nil else { return }
    perform {
      let displays = displayProvider()
      guard let display = cameraDockTarget(in: displays) else {
        setPersistentStatus("No display is available for Camera Dock. Connect or select a display.")
        return
      }
      let preferences = cameraDockPreferences(for: display)
      guard
        let next = FloatingPrompterWindowController(
          cameraDockOn: display, controller: self, preferences: preferences)
      else {
        setPersistentStatus(
          "Camera Dock does not fit this display. Choose a larger display or reduce text size."
        )
        return
      }

      try claimAndPrepare()
      state.cameraDockWidth = preferences.width
      state.cameraDockLineCount = preferences.lineCount
      state.cameraDockHorizontalNudge = preferences.horizontalNudge
      state.cameraDockNotchIsland = preferences.notchIslandEnabled

      let running = !session.voiceSessionActive && (session.state == .running || pendingResume)
      // Return to the display Output is on. The picker may already name the next
      // destination, which Output has not moved to and the operator has not confirmed.
      let previous: CameraDockReturnSurface =
        if let output {
          .output(String(output.displayID), session.logicalSize, wasRunning: running)
        } else if floating != nil {
          .floating(session.logicalSize, wasRunning: running)
        } else {
          .preview(session.logicalSize, wasRunning: running)
        }
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = false
      output?.onClose = nil
      output?.close()
      output = nil
      floating?.onClose = nil
      floating?.close()
      floating = next
      cameraDockReturnSurface = previous
      state.cameraDockReady = true
      let ephemeral = ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] == "1"
      state.cameraDockFirstUseCalloutVisible =
        !cameraDockFirstUseAcknowledgedInProcess
        && (ephemeral || !UserDefaults.standard.bool(forKey: Self.cameraDockExplainerSeenKey))
      session.logicalSize = next.viewportSize
      next.reflection.viewport.driver = DisplayLinkDriver(
        viewport: next.reflection.viewport, session: session)
      next.reflection.viewport.driver?.authoritative = true
      next.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
      next.onClose = { [weak self] in
        guard let self else { return }
        self.pendingAnchor =
          self.cameraDock?.reflection.viewport.captureAnchor()
          ?? self.pendingAnchor
        let restoredSize = self.cameraDockReturnSurface?.logicalSize ?? self.session.logicalSize
        self.cameraDockReturnSurface = nil
        self.perform { try self.session.pauseSafely("Camera Dock stopped — position retained") }
        self.floating = nil
        self.session.logicalSize = restoredSize
        self.state.cameraDockReady = false
        self.state.cameraDockFirstUseCalloutVisible = false
        self.render()
        self.refresh()
      }
      render()
      next.showWindow(nil)
      showControls()
      refresh()
    }
  }

  @objc func cameraDockAction() { showCameraDock() }

  func showFloating() {
    perform {
      try claimAndPrepare()
      cameraDockReturnSurface = nil
      state.cameraDockReady = false
      state.cameraDockFirstUseCalloutVisible = false
      let running = !session.voiceSessionActive && (session.state == .running || pendingResume)
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = running
      output?.onClose = nil
      output?.close()
      output = nil
      floating?.onClose = nil
      floating?.close()
      guard let screen = window?.screen ?? NSScreen.main else { return }
      let next = FloatingPrompterWindowController(screen: screen, controller: self)
      floating = next
      session.logicalSize = next.window?.contentView?.bounds.size ?? CGSize(width: 800, height: 400)
      next.reflection.viewport.driver = DisplayLinkDriver(
        viewport: next.reflection.viewport, session: session)
      next.reflection.viewport.driver?.authoritative = true
      next.reflection.viewport.driver?.onError = { [weak self] in self?.present($0) }
      next.onClose = { [weak self] in
        guard let self else { return }
        self.perform { try self.session.pauseSafely("Floating prompter stopped") }
        self.floating = nil
        self.refresh()
      }
      render()
      next.showWindow(nil)
      showControls()
      refresh()
    }
  }
  private func preservePreparationAnchor() {
    if pendingAnchor == nil { pendingAnchor = authoritative.captureAnchor() }
  }
  func cancelPendingNavigation() {
    pendingAnchor = nil
  }
  func scrub(delta: Double, momentum: Bool) {
    if !momentum { cancelPendingNavigation() }
    perform {
      try session.scrub(delta: delta, momentum: momentum)
      applyCurrentPosition()
    }
  }
  func seek(_ position: Double) {
    cancelPendingNavigation()
    perform {
      try session.seek(position)
      applyCurrentPosition()
    }
  }
  func resumeAfterMeasurement() {
    guard !session.voiceSessionActive else {
      pendingResume = false
      return
    }
    if session.measuring {
      pendingResume = true
    } else {
      perform {
        let saved = session.countdownSeconds
        session.countdownSeconds = 0
        defer { session.countdownSeconds = saved }
        try session.toggle(script)
      }
    }
  }
  func floatingResized() {
    guard let floating, let size = floating.window?.contentView?.bounds.size else { return }
    perform {
      let running = !session.voiceSessionActive && (session.state == .running || pendingResume)
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = running
      session.logicalSize = size
      render()
    }
  }
  func updateFloatingOptions() {
    floating?.root?.grip.alphaValue = session.state == .running ? 0 : 1
    if cameraDock == nil {
      floating?.window?.backgroundColor = NSColor.black.withAlphaComponent(
        state.clickThrough && session.state == .running ? 0 : 0.02)
    }
    floating?.window?.alphaValue =
      cameraDock != nil
      ? 1 : min(1, max(0.3, state.floatingOpacity))
    floating?.window?.collectionBehavior =
      cameraDock != nil
      ? [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
      : state.overFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    var inks = [state.style.foregroundRGBA]
    if state.style.mode == .preserveSource {
      inks = []
      let source = session.snapshot?.attributed ?? script.source
      source.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: source.length)) {
        value, _, _ in
        let color = (value as? NSColor ?? .black).usingColorSpace(.sRGB)
        if let color {
          inks.append([
            color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent,
          ])
        }
      }
    }
    let ratio =
      inks.map {
        Contrast.worst(
          text: $0, background: state.style.backgroundRGBA,
          windowAlpha: cameraDock == nil ? state.floatingOpacity : 1,
          panelAlpha: state.style.textPanelOpacity)
      }.min() ?? 1
    state.contrastWarning =
      ratio < 4.5
      ? String(
        format: "Low contrast (%.1f:1 over some backgrounds). Increase opacity or change colors.",
        ratio) : ""
  }

  func cameraDockResized(to size: CGSize) {
    guard cameraDock != nil else { return }
    perform {
      let running = !session.voiceSessionActive && (session.state == .running || pendingResume)
      try session.pause()
      preservePreparationAnchor()
      pendingPlay = false
      pendingResume = running
      session.logicalSize = size
      render()
    }
  }

  func displayDescriptor(on screen: NSScreen) -> DisplayDescriptor? {
    displayProvider().first { $0.screen == screen }
  }

  func cameraDockMenuTitle(for displays: [DisplayDescriptor]) -> String {
    if cameraDock?.dockLocation == .camera { return "Camera Dock" }
    guard let display = cameraDockTarget(in: displays) else { return "Camera Dock" }
    return CameraDockDisplaySelection.menuTitle(
      isBuiltIn: display.isBuiltIn && !display.isMirrored,
      isMirrored: display.isMirrored,
      safeTop: CameraDockGeometry.cameraSafeAreaHeight(on: display.cameraDockParameters),
      islandEnabled: cameraDockPreferences(for: display).notchIslandEnabled)
  }

  func cameraDockTarget(in displays: [DisplayDescriptor]) -> DisplayDescriptor? {
    let candidates = displays.map {
      CameraDockDisplayCandidate(
        id: $0.selectionKey, isBuiltIn: $0.isBuiltIn, isMirrored: $0.isMirrored)
    }
    guard
      let id = CameraDockDisplaySelection.preferred(
        in: candidates, selectedID: state.selectedDisplay)
    else { return nil }
    return displays.first { $0.selectionKey == id }
  }

  /// The Display picker. The Camera Dock inspector values follow the new target at once,
  /// so an edit made on the newly chosen display persists that display's own width and
  /// line count rather than the previous display's.
  func selectDisplay(_ key: String) {
    guard state.selectedDisplay != key else { return }
    state.selectedDisplay = key
    refreshCameraDockPreferencesForTarget()
    if state.cameraDockPlacementPreviewExpanded { render() }
  }

  private func cameraDockPreferences(for display: DisplayDescriptor) -> CameraDockPreferences {
    cameraDockPreferenceCatalog.preference(
      forDisplayUUID: display.preference.uuid ?? display.preference.name,
      screenWidth: Double(display.screen.frame.width))
  }

  private func refreshCameraDockPreferencesForTarget(
    displays suppliedDisplays: [DisplayDescriptor]? = nil
  ) {
    let displays = suppliedDisplays ?? displayProvider()
    guard cameraDock == nil else { return }
    guard let display = cameraDockTarget(in: displays) else {
      state.cameraDockWidth = CameraDockGeometry.minimumWidth
      state.cameraDockLineCount = CameraDockGeometry.defaultLineCount
      state.cameraDockHorizontalNudge = 0
      return
    }
    let preference = cameraDockPreferences(for: display)
    state.cameraDockWidth = preference.width
    state.cameraDockLineCount = preference.lineCount
    state.cameraDockHorizontalNudge = preference.horizontalNudge
    state.cameraDockNotchIsland = preference.notchIslandEnabled
  }

  private var cameraDockIslandPreference: Bool? { state.cameraDockNotchIsland ? nil : false }

  private func persistCameraDockPreferences(
    _ preference: CameraDockPreferences, for display: DisplayDescriptor
  ) {
    cameraDockPreferenceCatalog.set(
      preference, forDisplayUUID: display.preference.uuid ?? display.preference.name)
    guard ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" else { return }
    perform {
      UserDefaults.standard.set(
        try JSONEncoder().encode(cameraDockPreferenceCatalog), forKey: "cameraDockPreferences")
    }
  }

  private func setCameraDockPreference(_ preference: CameraDockPreferences) {
    let normalized = preference.normalized()
    state.cameraDockWidth = normalized.width
    state.cameraDockLineCount = normalized.lineCount
    state.cameraDockHorizontalNudge = normalized.horizontalNudge
    state.cameraDockNotchIsland = normalized.notchIslandEnabled
    let displays = displayProvider()
    let display =
      cameraDock.flatMap { dock in displays.first { $0.id == dock.displayID } }
      ?? cameraDockTarget(in: displays)
    guard let display else { return }
    persistCameraDockPreferences(normalized, for: display)
    if let cameraDock {
      guard
        cameraDock.updateCameraDockPlacement(
          on: display, preferences: normalized, style: session.style)
      else {
        cameraDockPlacementUnavailable()
        render()
        return
      }
    } else if state.cameraDockPlacementPreviewExpanded {
      render()
    }
  }

  func setCameraDockWidth(_ width: Double) {
    setCameraDockPreference(
      CameraDockPreferences(
        width: width, lineCount: state.cameraDockLineCount,
        horizontalNudge: state.cameraDockHorizontalNudge,
        forceNotchAttachment: cameraDockIslandPreference))
  }

  /// Draws the island around an emulated housing on displays without a notch, or the
  /// plain tray below the menu bar when off. Displays with a notch always attach.
  func setCameraDockNotchIsland(_ enabled: Bool) {
    setCameraDockPreference(
      CameraDockPreferences(
        width: state.cameraDockWidth, lineCount: state.cameraDockLineCount,
        horizontalNudge: state.cameraDockHorizontalNudge,
        forceNotchAttachment: enabled ? nil : false))
  }

  func setCameraDockLineCount(_ lineCount: Int) {
    setCameraDockPreference(
      CameraDockPreferences(
        width: state.cameraDockWidth, lineCount: lineCount,
        horizontalNudge: state.cameraDockHorizontalNudge,
        forceNotchAttachment: cameraDockIslandPreference))
  }

  func setCameraDockHorizontalNudge(_ nudge: Double) {
    setCameraDockPreference(
      CameraDockPreferences(
        width: state.cameraDockWidth, lineCount: state.cameraDockLineCount,
        horizontalNudge: nudge, forceNotchAttachment: cameraDockIslandPreference))
  }

  func resetCameraDockPreferences() {
    guard
      let display = cameraDock.flatMap({ dock in
        displayProvider().first { $0.id == dock.displayID }
      }) ?? cameraDockTarget(in: displayProvider())
    else { return }
    setCameraDockPreference(.defaults(screenWidth: Double(display.screen.frame.width)))
  }

  private func cameraDockPlacementUnavailable() {
    guard let cameraDock else { return }
    pendingAnchor = cameraDock.reflection.viewport.captureAnchor() ?? pendingAnchor
    let restoredSize = cameraDockReturnSurface?.logicalSize ?? session.logicalSize
    cameraDockReturnSurface = nil
    let message =
      "Camera Dock unavailable — position retained. Choose a larger display or reduce text size."
    perform { try session.pauseSafely(message) }
    cameraDock.onClose = nil
    cameraDock.close()
    floating = nil
    session.logicalSize = restoredSize
    state.cameraDockReady = false
    state.cameraDockFirstUseCalloutVisible = false
    refresh()
    setPersistentStatus(message)
  }
  func updateReadout() {
    func stamp(_ seconds: Double) -> String {
      let value = max(0, Int(seconds))
      return String(format: "%02d:%02d", value / 60, value % 60)
    }
    readout.elapsed = stamp(session.elapsedSeconds)
    readout.remaining = session.remainingSeconds.map { stamp($0) } ?? "—"
    // One pill vocabulary across the take bar and the Controls panel (Quiet Studio ⑩).
    readout.status =
      session.measuring
      ? "Measuring…"
      : session.state == .countingDown
        ? "Starting · \(session.countdownDigit ?? 0)"
        : session.state == .running
          ? "Playing"
          : session.state == .idle
            ? (script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "Empty" : "Ready")
            : session.message.hasPrefix("End of script") ? "End of script" : "Paused"
    let lpm = session.state == .idle ? state.speed : session.effectiveLPM
    readout.pace =
      String(format: "%.0f lpm", lpm)
      + (abs(lpm - session.preferredLPM) > 0.05 && session.state != .idle ? " (limited)" : "")
    readout.wpm =
      session.lines > 0 && session.state != .idle
      ? String(format: "≈ %.0f wpm", lpm * Double(session.words) / Double(session.lines))
      : "≈ — wpm"
    if let end = session.timeline.upperBound, end > 0 {
      readout.progress = min(1, max(0, session.timeline.anchorPosition / end))
    } else {
      readout.progress = 0
    }
  }
  func updateProgressTimer() {
    let active = session.state == .running || session.state == .countingDown
    if active, progressTimer == nil {
      progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.progressTick() }
      }
      if let progressTimer { RunLoop.main.add(progressTimer, forMode: .common) }
    }
    if !active {
      progressTimer?.invalidate()
      progressTimer = nil
      restoreChrome()
    }
  }
  func progressTick() {
    updateReadout()
    updateEditorParagraph()
    if let end = session.timeline.upperBound, end > 0 {
      perform { readout.progress = try session.position(at: session.effectiveTime) / end }
    }
    let point = NSEvent.mouseLocation
    let overApp = [window, output?.window, floating?.window, panel?.window].compactMap { $0 }
      .contains { $0.isVisible && $0.frame.contains(point) }
    if overApp, point != lastPointer {
      lastPointerTime = session.clock()
      restoreChrome()
    }
    lastPointer = point
    if state.hideControls, session.state == .running, session.clock() - lastPointerTime >= 2 {
      let alpha = 0.08
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        transportChrome.alphaValue = alpha
        panel?.window?.alphaValue = alpha
      } else {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.2
          transportChrome.animator().alphaValue = alpha
          panel?.window?.animator().alphaValue = alpha
        }
      }
      window?.toolbar?.isVisible = false
      for item in window?.toolbar?.items ?? [] { item.view?.alphaValue = alpha }
    }
  }
  func restoreChrome() {
    window?.toolbar?.isVisible = true
    transportChrome.alphaValue = 1
    panel?.window?.alphaValue = 1
    for item in window?.toolbar?.items ?? [] { item.view?.alphaValue = 1 }
  }
  @objc func editorUndoChanged(_ notification: Notification) {
    script.updateChangeCount(
      notification.name == .NSUndoManagerDidUndoChange ? .changeUndone : .changeRedone)
    guard !replacingEditor else { return }
    if session.state == .idle, editor.string != script.source.string {
      replacingEditor = true
      script.replaceSource(editor.attributedString(), registerUndo: false)
      replacingEditor = false
    }
    let speed = script.model.preferredSpeedLinesPerMinute
    if speed != state.speed {
      perform {
        try session.speed(speed)
        state.speed = session.preferredLPM
        refresh()
      }
    }
    if session.state == .idle || session.snapshot?.revision == script.revision {
      syncStyleAfterUndo()
    }
  }
  @objc func editorUndoGroupClosed(_ notification: Notification) {
    guard let undoManager = notification.object as? UndoManager else { return }
    guard
      undoManager.groupingLevel == 0, !undoManager.isUndoing, !undoManager.isRedoing
    else { return }
    script.updateChangeCount(.changeDone)
  }
  @objc func toggleInspector() {
    guard let item = inspectorItem, let window else { return }
    if item.isCollapsed, window.frame.width < 1002, let screen = window.screen {
      if screen.visibleFrame.width < 1002, let content = window.contentView {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = CGSize(width: 300, height: min(640, screen.visibleFrame.height - 60))
        popover.contentViewController = NSHostingController(
          rootView: OperatorControls(state: state, controller: self))
        inspectorPopover = popover
        popover.show(
          relativeTo: CGRect(
            x: content.bounds.maxX - 32, y: content.bounds.maxY - 32, width: 24, height: 24),
          of: content, preferredEdge: .minX)
        return
      }
      var frame = window.frame
      frame.size.width = min(1002, screen.visibleFrame.width)
      window.setFrame(FrameClamp.clamp(frame, to: screen.visibleFrame), display: true)
    }
    inspectorWidthConstraint?.isActive = item.isCollapsed
    item.isCollapsed.toggle()
    userCollapsedInspector = item.isCollapsed
    balancePanes()
    if ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" {
      UserDefaults.standard.set(item.isCollapsed, forKey: "inspectorCollapsed")
    }
  }
  func balancePanes() {
    guard let window else { return }
    let width = window.contentLayoutRect.width
    if width < 1002, inspectorItem?.isCollapsed == false {
      inspectorWidthConstraint?.isActive = false
      inspectorItem?.isCollapsed = true
    }
    inspectorWidthConstraint?.isActive = inspectorItem?.isCollapsed == false
    let inspectorWidth = inspectorItem?.isCollapsed == true ? 0.0 : (width >= 1100 ? 280.0 : 260.0)
    editorWidthConstraint?.constant = min(420, max(320, width - inspectorWidth - 422))
    inspectorWidthConstraint?.constant = inspectorWidth > 0 ? inspectorWidth : 280
    window.contentView?.layoutSubtreeIfNeeded()
  }

  func updateEditorParagraph() {
    let offset = session.state == .idle ? nil : authoritative.captureAnchor()?.utf16Offset
    if editor.currentTakeOffset != offset {
      editor.currentTakeOffset = offset
      editor.needsDisplay = true
    }
  }
  func windowDidResize(_ notification: Notification) {
    if let window, window.contentLayoutRect.width >= 1002, !userCollapsedInspector,
      inspectorItem?.isCollapsed == true
    {
      inspectorItem?.isCollapsed = false
    }
    balancePanes()
  }
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .init("transport"), .init("present"), .init("inspector"), .init("editorSeparator"),
      .init("inspectorSeparator"),
      .flexibleSpace,
    ]
  }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .init("editorSeparator"), .flexibleSpace, .init("transport"), .flexibleSpace,
      .init("present"),
      .init("inspectorSeparator"), .init("inspector"),
    ]
  }
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    if id.rawValue == "editorSeparator" {
      return NSTrackingSeparatorToolbarItem(
        identifier: id, splitView: splitController.splitView, dividerIndex: 0)
    }
    if id.rawValue == "inspectorSeparator" {
      return NSTrackingSeparatorToolbarItem(
        identifier: id, splitView: splitController.splitView, dividerIndex: 1)
    }
    if id.rawValue == "transport" {
      let item = NSToolbarItemGroup(itemIdentifier: id)
      item.label = "Playback"
      let row = NSStackView()
      row.spacing = 6
      for (symbol, label, command) in [
        ("backward.end.fill", "Restart · Home", PlaybackCommand.restart),
        ("chevron.up", "Previous paragraph · Page Up", .previousParagraph),
        ("play.fill", "Play or pause · Space", .toggle),
        ("chevron.down", "Next paragraph · Page Down", .nextParagraph),
        ("arrow.up.arrow.down", "Reverse direction · R", .reverse),
      ] {
        let button = ActionButton(symbol: symbol, label: label) { [weak self] in
          self?.execute(command)
        }
        button.playbackCommand = command
        button.widthAnchor.constraint(equalToConstant: command == .toggle ? 42 : 28).isActive = true
        if command == .toggle {
          playToolbarButton = button
          button.bezelStyle = .circular
          button.wantsLayer = true
          button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
          button.layer?.cornerRadius = 12
          button.bezelColor = .controlAccentColor
          button.contentTintColor = .white
        }
        row.addArrangedSubview(button)
      }
      item.view = row
      return item
    }
    if id.rawValue == "present" {
      // A plain item keeps the custom pull-down; NSMenuToolbarItem drops a custom view, so the
      // live "Presenting · …" chip would never reach the screen.
      let item = NSToolbarItem(itemIdentifier: id)
      item.label = "Present"
      item.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Present")
      let button = NSPopUpButton(frame: .zero, pullsDown: true)
      let menu = presentationMenu()
      let title = NSMenuItem(title: "Present", action: nil, keyEquivalent: "")
      title.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
      menu.insertItem(title, at: 0)
      button.menu = menu
      button.bezelStyle = .texturedRounded
      button.setAccessibilityLabel("Present")
      item.view = button
      return item
    }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = "Inspector"
    item.view = ActionButton(symbol: "sidebar.right", label: "Toggle Inspector · ⌃⌘I") {
      [weak self] in self?.toggleInspector()
    }
    return item
  }
  func presentationMenu() -> NSMenu {
    let menu = NSMenu(title: "Present")
    for display in DisplayDescriptor.all() {
      let item = NSMenuItem(
        title: "Present on \(display.preference.name)", action: #selector(presentOnDisplay(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = display.selectionKey
      menu.addItem(item)
    }
    let floating = NSMenuItem(
      title: "Floating Prompter", action: #selector(floatingAction), keyEquivalent: "")
    floating.target = self
    menu.addItem(floating)
    let cameraDock = NSMenuItem(
      title: cameraDockMenuTitle, action: #selector(cameraDockAction), keyEquivalent: "")
    cameraDock.target = self
    menu.addItem(cameraDock)
    let stop = NSMenuItem(
      title: "Stop Presenting (Esc)", action: #selector(stopPresenting), keyEquivalent: "")
    stop.target = self
    menu.addItem(stop)
    return menu
  }
  @objc func presentOnDisplay(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    if output != nil {
      output?.onClose = nil
      output?.close()
      output = nil
    }
    selectDisplay(key)
    showOutput()
  }
  @objc func floatingAction() { showFloating() }
  @objc func stopPresenting() { hideOutput() }
  @objc func controlsAction() { showControls() }
  @objc func saveCloudAction() { saveICloud() }
  @objc func downloadAction() { requestDownload() }
  @objc func refreshCloudAction() { Task { await script.refreshCloudStatus() } }
  @objc func stopTakeAction() { stop() }
}
