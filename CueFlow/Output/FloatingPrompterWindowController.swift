import AppKit
import CueFlowCore
import SwiftUI

@MainActor final class PresentationPanel: NSPanel {
  weak var operatorController: OperatorWindowController?
  override var canBecomeKey: Bool { true }
  override func keyDown(with event: NSEvent) {
    if !CommandRouter.route(event, window: self, controller: operatorController) {
      super.keyDown(with: event)
    }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      CommandRouter.route(event, window: self, controller: operatorController)
    {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
enum PrompterPlacement: Equatable {
  case floating
  case cameraDock
}

@MainActor final class FloatingPrompterWindowController: NSWindowController, NSWindowDelegate {
  let reflection = ReflectionContainerView(frame: .zero)
  let placement: PrompterPlacement
  var onClose: (() -> Void)?
  var root: FloatingRoot?
  var displayID: CGDirectDisplayID?
  private(set) var displayUUID: String?
  private(set) var dockPreferences: CameraDockPreferences
  private(set) var dockLocation: CameraDockLocation = .topOfDisplay
  weak var operatorController: OperatorWindowController?

  var isCameraDock: Bool { placement == .cameraDock }
  var viewportSize: CGSize { root?.logicalSize ?? window?.contentView?.bounds.size ?? .zero }

  init(screen: NSScreen, controller: OperatorWindowController) {
    placement = .floating
    operatorController = controller
    let display = DisplayDescriptor.all().first { $0.screen == screen }
    displayID = display?.id
    displayUUID = display?.preference.uuid ?? screen.localizedName
    dockPreferences = .defaults(screenWidth: screen.frame.width)
    let visible = screen.visibleFrame
    var frame = CGRect(
      x: visible.midX - visible.width * 0.2, y: visible.maxY - visible.height * 0.3,
      width: visible.width * 0.4, height: visible.height * 0.3)
    let key =
      "floatingFrame-"
      + (DisplayDescriptor.all().first { $0.screen == screen }?.preference.uuid
        ?? screen.localizedName)
    if let stored = UserDefaults.standard.string(forKey: key) {
      let relative = NSRectFromString(stored)
      frame = relative.offsetBy(dx: visible.minX, dy: visible.minY)
    }
    frame = FrameClamp.clamp(frame, to: visible)
    let window = PresentationPanel(
      contentRect: frame,
      styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    super.init(window: window)
    configure(window: window, controller: controller, screen: screen, viewportSize: frame.size)
  }

  init?(
    cameraDockOn display: DisplayDescriptor, controller: OperatorWindowController,
    preferences: CameraDockPreferences
  ) {
    placement = .cameraDock
    operatorController = controller
    dockPreferences = preferences.normalized()
    let screen = display.screen
    displayID = display.id
    displayUUID = display.preference.uuid ?? screen.localizedName
    guard
      let geometry = Self.cameraDockGeometry(
        display: display, preferences: dockPreferences, style: controller.state.style)
    else { return nil }
    dockLocation = geometry.placement.location
    let window = PresentationPanel(
      contentRect: geometry.frame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false, screen: screen)
    super.init(window: window)
    configure(
      window: window, controller: controller, screen: screen, viewportSize: geometry.viewportSize)
    window.setFrame(geometry.frame, display: false)
  }

  private func configure(
    window: PresentationPanel, controller: OperatorWindowController, screen: NSScreen,
    viewportSize: CGSize
  ) {
    window.operatorController = controller
    window.title = isCameraDock ? "CueGlass · Camera Dock" : "CueGlass · Floating Prompter"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovable = !isCameraDock
    window.isMovableByWindowBackground = !isCameraDock
    window.hidesOnDeactivate = false
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.isOpaque = isCameraDock
    window.backgroundColor =
      isCameraDock
      ? NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1) : .clear
    window.minSize =
      isCameraDock ? CGSize(width: 360, height: 120) : CGSize(width: 320, height: 180)
    if isCameraDock {
      window.collectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
      ]
    }
    let root = FloatingRoot(reflection: reflection, controller: controller, placement: placement)
    root.logicalSize = viewportSize
    self.root = root
    window.contentView = root
    window.delegate = self
    window.acceptsMouseMovedEvents = true
    reflection.wantsLayer = true
    reflection.layer?.cornerRadius = 14
    reflection.layer?.masksToBounds = true
    reflection.viewport.compactCountdown = isCameraDock
    if isCameraDock {
      root.setAccessibilityElement(true)
      root.setAccessibilityLabel("CueGlass prompt")
      if let controls = root.cameraDockControls {
        root.setAccessibilityChildren(controls.accessibilityControls)
        window.initialFirstResponder = controls.closeButton
        window.recalculateKeyViewLoop()
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("Use an explicit presentation initializer") }

  private static func cameraDockGeometry(
    display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> (placement: CameraDockPlacement, frame: CGRect, viewportSize: CGSize)? {
    guard
      let viewportHeight = CameraDockGeometry.viewportHeight(
        lineAdvance: PresentationFont.lineAdvance(style), lineCount: preferences.lineCount)
    else { return nil }
    let viewportSize = CGSize(width: preferences.width, height: viewportHeight)
    let panelHeight = viewportHeight + 44
    guard
      let placement = CameraDockGeometry.placement(
        on: display.cameraDockParameters, isBuiltIn: display.isBuiltIn && !display.isMirrored,
        width: preferences.width, height: panelHeight, horizontalNudge: preferences.horizontalNudge)
    else { return nil }
    let frame = CGRect(
      x: placement.frame.x, y: placement.frame.y, width: placement.frame.width,
      height: placement.frame.height)
    return (placement, frame, viewportSize)
  }

  @discardableResult func updateCameraDockPlacement(
    on display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    let priorSize = viewportSize
    guard applyCameraDockPresentation(on: display, preferences: preferences, style: style) else {
      return false
    }
    if priorSize != viewportSize { operatorController?.cameraDockResized(to: viewportSize) }
    return true
  }

  @discardableResult func updateCameraDockPresentation(style: ReadingStyle) -> CGSize? {
    guard isCameraDock, let screen = window?.screen,
      let display = operatorController?.displayProvider().first(where: { $0.id == displayID })
        ?? operatorController?.displayDescriptor(on: screen),
      applyCameraDockPresentation(on: display, preferences: dockPreferences, style: style)
    else { return nil }
    return viewportSize
  }

  private func applyCameraDockPresentation(
    on display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    guard isCameraDock, let window,
      let geometry = Self.cameraDockGeometry(
        display: display, preferences: preferences, style: style)
    else { return false }
    dockPreferences = preferences.normalized()
    dockLocation = geometry.placement.location
    displayID = display.id
    displayUUID = display.preference.uuid ?? display.screen.localizedName
    window.setFrame(geometry.frame, display: true)
    root?.logicalSize = geometry.viewportSize
    return true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    if !isCameraDock { operatorController?.floatingResized() }
    saveFrame()
  }
  func windowDidMove(_ notification: Notification) { saveFrame() }
  func windowDidChangeScreen(_ notification: Notification) {
    if !isCameraDock, let screen = window?.screen {
      displayID = operatorController?.displayDescriptor(on: screen)?.id
    }
    if !isCameraDock { saveFrame() }
  }
  private func saveFrame() {
    guard !isCameraDock, ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1",
      let window,
      let screen = window.screen
    else { return }
    let key =
      "floatingFrame-"
      + (DisplayDescriptor.all().first { $0.screen == screen }?.preference.uuid
        ?? screen.localizedName)
    UserDefaults.standard.set(
      NSStringFromRect(
        window.frame.offsetBy(dx: -screen.visibleFrame.minX, dy: -screen.visibleFrame.minY)),
      forKey: key)
  }
  func windowWillClose(_ notification: Notification) {
    reflection.viewport.driver?.stop()
    onClose?()
  }
}

@MainActor final class FloatingRoot: NSView {
  let reflection: ReflectionContainerView
  let grip: NSVisualEffectView
  let cameraDockControls: CameraDockControlsView?
  let placement: PrompterPlacement
  weak var controller: OperatorWindowController?
  var logicalSize = CGSize(width: 800, height: 400) { didSet { needsLayout = true } }
  private var tracking: NSTrackingArea?
  init(
    reflection: ReflectionContainerView, controller: OperatorWindowController,
    placement: PrompterPlacement = .floating
  ) {
    self.reflection = reflection
    self.controller = controller
    self.placement = placement
    grip = NSVisualEffectView()
    grip.material = .hudWindow
    grip.blendingMode = .withinWindow
    grip.state = .active
    grip.alphaValue = controller.session.state == .running ? 0 : 1
    grip.appearance = NSAppearance(named: .darkAqua)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
      grip.wantsLayer = true
      grip.layer?.backgroundColor =
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor
    }
    let content: NSView
    if placement == .cameraDock {
      let controls = CameraDockControlsView(controller: controller)
      cameraDockControls = controls
      content = controls
    } else {
      cameraDockControls = nil
      content = NSHostingView(
        rootView: AnyView(FloatingGrip(state: controller.state, controller: controller)))
    }
    content.translatesAutoresizingMaskIntoConstraints = false
    grip.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: grip.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: grip.trailingAnchor),
      content.topAnchor.constraint(equalTo: grip.topAnchor),
      content.bottomAnchor.constraint(equalTo: grip.bottomAnchor),
    ])
    super.init(frame: .zero)
    addSubview(reflection)
    addSubview(grip)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.masksToBounds = true
    if placement == .cameraDock {
      layer?.backgroundColor = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1).cgColor
    }
  }
  required init?(coder: NSCoder) { fatalError("Use init(reflection:controller:)") }
  override func layout() {
    super.layout()
    if placement == .cameraDock {
      let gripHeight = min(44, bounds.height)
      reflection.frame = CGRect(
        x: 0, y: gripHeight, width: bounds.width, height: max(0, bounds.height - gripHeight))
      grip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: gripHeight)
    } else {
      reflection.frame = bounds
      let height = controller?.state.contrastWarning.isEmpty == false ? 52.0 : 28.0
      grip.frame = CGRect(
        x: 0, y: max(0, bounds.height - height), width: bounds.width, height: height)
    }
    reflection.setBoundsSize(logicalSize)
    reflection.needsLayout = true
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) {
    grip.alphaValue = 1
  }
  override func mouseExited(with event: NSEvent) {
    grip.alphaValue = controller?.session.state == .running ? 0 : 1
  }
  func updateCameraDockControls() {
    cameraDockControls?.refresh()
  }
}
struct FloatingGrip: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  var body: some View {
    VStack(spacing: 2) {
      HStack {
        Button {
          controller.hideOutput()
        } label: {
          Image(systemName: "xmark")
        }.help("Stop Presenting · Escape").accessibilityLabel("Stop presenting")
        Image(systemName: "line.3.horizontal")
        Slider(value: $state.floatingOpacity, in: 0.3...1).onChange(of: state.floatingOpacity) {
          controller.updateFloatingOptions()
          controller.saveOperatorPreferences()
        }.accessibilityLabel("Whole window opacity")
        Button {
          controller.state.horizontal.toggle()
          controller.reflect()
        } label: {
          Image(systemName: "arrow.left.and.right")
        }.accessibilityLabel("Reflect horizontally")
        Button {
          controller.toggle()
        } label: {
          Image(systemName: state.running ? "pause.fill" : "play.fill")
          Text(state.running ? "Pause" : "Resume").font(.system(size: 11, weight: .medium))
        }.accessibilityLabel("Play or Pause · Space")
      }.buttonStyle(.borderless).controlSize(.small).frame(height: 28).padding(.horizontal, 6)
      if !state.contrastWarning.isEmpty { Text(state.contrastWarning).font(.caption2).lineLimit(2) }
    }.foregroundStyle(.primary)
  }
}

@MainActor struct CameraDockGrip {
  static let closeAccessibilityLabel = "Close Camera Dock"
  static let playbackAccessibilityLabel = "Play or pause"
  static let adjustAccessibilityLabel = "Adjust Camera Dock"

  let state: OperatorState
  unowned let controller: OperatorWindowController

  var canPlay: Bool {
    !controller.script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var statusText: String {
    if controller.cameraDockCameraMayBeElsewhere {
      let status = state.running ? "Playing" : "Paused"
      return "\(status) · camera may be on another display"
    }
    if state.voiceActive && !state.voiceMessage.isEmpty { return state.voiceMessage }
    if state.running { return "Playing" }
    if controller.session.snapshot?.attributed.string.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    .isEmpty == true {
      return "Ready"
    }
    return controller.session.state == .idle ? "Ready" : "Paused · Space to resume"
  }
}

@MainActor final class CameraDockControlsView: NSView {
  weak var controller: OperatorWindowController?
  let closeButton = NSButton(frame: .zero)
  let playbackButton = NSButton(frame: .zero)
  let adjustButton = NSPopUpButton(frame: .zero, pullsDown: true)
  private let statusLabel = NSTextField(labelWithString: "Ready")

  var accessibilityControls: [NSView] { [closeButton, playbackButton, adjustButton] }

  init(controller: OperatorWindowController) {
    self.controller = controller
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    configure(
      closeButton, symbol: "xmark", label: CameraDockGrip.closeAccessibilityLabel,
      help: "Return to the previous presentation surface · Escape", action: #selector(closeDock))
    configure(
      playbackButton, symbol: "play.fill", label: CameraDockGrip.playbackAccessibilityLabel,
      help: "Play or pause · Space", action: #selector(togglePlayback))
    configureAdjustMenu()

    statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.setAccessibilityElement(false)

    closeButton.nextKeyView = playbackButton
    playbackButton.nextKeyView = adjustButton
    adjustButton.nextKeyView = closeButton
    for view in [closeButton, playbackButton, statusLabel, adjustButton] { addSubview(view) }
    setAccessibilityElement(false)
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("Use init(controller:)") }

  override func layout() {
    super.layout()
    let inset: CGFloat = min(6, max(0, bounds.width / 2))
    let gap: CGFloat = 6
    let buttonHeight: CGFloat = min(28, bounds.height)
    let buttonY = max(0, (bounds.height - buttonHeight) / 2)
    let available = max(0, bounds.width - inset * 2)
    let closeWidth = min(28, available)
    let playbackWidth = min(28, max(0, available - closeWidth - gap))
    let adjustWidth = min(32, max(0, available - closeWidth - playbackWidth - gap * 2))
    let closeX = inset
    let playbackX = closeX + closeWidth + gap
    let adjustX = bounds.width - inset - adjustWidth
    let statusX = playbackX + playbackWidth + gap
    let statusWidth = max(0, adjustX - gap - statusX)

    closeButton.frame = CGRect(x: closeX, y: buttonY, width: closeWidth, height: buttonHeight)
    playbackButton.frame = CGRect(
      x: playbackX, y: buttonY, width: playbackWidth, height: buttonHeight)
    statusLabel.frame = CGRect(
      x: statusX, y: buttonY, width: statusWidth, height: buttonHeight)
    adjustButton.frame = CGRect(x: adjustX, y: buttonY, width: adjustWidth, height: buttonHeight)
  }

  private func configure(
    _ button: NSButton, symbol: String, label: String, help: String, action: Selector
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    button.title = ""
    button.bezelStyle = .texturedRounded
    button.controlSize = .small
    button.refusesFirstResponder = false
    button.setAccessibilityElement(true)
    button.setAccessibilityRole(.button)
    button.setAccessibilityLabel(label)
    button.setAccessibilityHelp(help)
    button.toolTip = help
    button.target = self
    button.action = action
  }

  private func configureAdjustMenu() {
    adjustButton.controlSize = .small
    adjustButton.refusesFirstResponder = false
    adjustButton.setAccessibilityElement(true)
    adjustButton.setAccessibilityRole(.popUpButton)
    adjustButton.setAccessibilityLabel(CameraDockGrip.adjustAccessibilityLabel)
    adjustButton.setAccessibilityHelp("Adjust Camera Dock width, visible lines, and position")
    adjustButton.toolTip = "Adjust Camera Dock width, visible lines, and horizontal position"
    adjustButton.addItem(withTitle: "Adjust")
    adjustButton.item(at: 0)?.image = NSImage(
      systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
    adjustButton.imagePosition = .imageOnly
    guard let menu = adjustButton.menu else { return }
    menu.addItem(NSMenuItem.separator())
    addMenuItem("Wider", to: menu, action: #selector(increaseWidth))
    addMenuItem("Narrower", to: menu, action: #selector(decreaseWidth))
    addMenuItem("Show More Lines", to: menu, action: #selector(increaseLineCount))
    addMenuItem("Show Fewer Lines", to: menu, action: #selector(decreaseLineCount))
    addMenuItem("Move Right", to: menu, action: #selector(nudgeRight))
    addMenuItem("Move Left", to: menu, action: #selector(nudgeLeft))
    menu.addItem(NSMenuItem.separator())
    addMenuItem("Reset Placement", to: menu, action: #selector(resetPlacement))
  }

  private func addMenuItem(_ title: String, to menu: NSMenu, action: Selector) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }

  func refresh() {
    guard let controller else { return }
    let grip = CameraDockGrip(state: controller.state, controller: controller)
    statusLabel.stringValue = grip.statusText
    playbackButton.isEnabled = grip.canPlay
    playbackButton.image = NSImage(
      systemSymbolName: controller.state.running ? "pause.fill" : "play.fill",
      accessibilityDescription: CameraDockGrip.playbackAccessibilityLabel)
  }

  @objc private func closeDock() { controller?.hideOutput() }
  @objc private func togglePlayback() { controller?.toggle() }
  @objc private func increaseWidth() {
    guard let controller else { return }
    controller.setCameraDockWidth(controller.state.cameraDockWidth + 20)
  }
  @objc private func decreaseWidth() {
    guard let controller else { return }
    controller.setCameraDockWidth(controller.state.cameraDockWidth - 20)
  }
  @objc private func increaseLineCount() {
    guard let controller else { return }
    controller.setCameraDockLineCount(controller.state.cameraDockLineCount + 1)
  }
  @objc private func decreaseLineCount() {
    guard let controller else { return }
    controller.setCameraDockLineCount(controller.state.cameraDockLineCount - 1)
  }
  @objc private func nudgeRight() {
    guard let controller else { return }
    controller.setCameraDockHorizontalNudge(controller.state.cameraDockHorizontalNudge + 8)
  }
  @objc private func nudgeLeft() {
    guard let controller else { return }
    controller.setCameraDockHorizontalNudge(controller.state.cameraDockHorizontalNudge - 8)
  }
  @objc private func resetPlacement() { controller?.resetCameraDockPreferences() }
}
