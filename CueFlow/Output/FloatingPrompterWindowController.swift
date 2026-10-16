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
    cameraDockOn screen: NSScreen, controller: OperatorWindowController,
    preferences: CameraDockPreferences
  ) {
    placement = .cameraDock
    operatorController = controller
    dockPreferences = preferences.normalized()
    let display = DisplayDescriptor.all().first { $0.screen == screen }
    displayID = display?.id
    displayUUID = display?.preference.uuid ?? screen.localizedName
    guard
      let geometry = Self.cameraDockGeometry(
        screen: screen, preferences: dockPreferences, style: controller.state.style)
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
    }
  }

  required init?(coder: NSCoder) { fatalError("Use an explicit presentation initializer") }

  private static func cameraDockGeometry(
    screen: NSScreen, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> (placement: CameraDockPlacement, frame: CGRect, viewportSize: CGSize)? {
    guard
      let viewportHeight = CameraDockGeometry.viewportHeight(
        lineAdvance: PresentationFont.lineAdvance(style), lineCount: preferences.lineCount)
    else { return nil }
    let isBuiltIn = DisplayDescriptor.all().first { $0.screen == screen }?.isBuiltIn == true
    let safeTop = isBuiltIn ? Double(screen.safeAreaInsets.top) : 0
    func coreRect(_ rect: CGRect?) -> CameraDockRect? {
      guard let rect else { return nil }
      return CameraDockRect(
        x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width),
        height: Double(rect.height))
    }
    let viewportSize = CGSize(width: preferences.width, height: viewportHeight)
    let panelHeight = viewportHeight + 44
    guard let screenFrame = coreRect(screen.frame),
      let visibleFrame = coreRect(screen.visibleFrame),
      let placement = CameraDockGeometry.placement(
        screenFrame: screenFrame, visibleFrame: visibleFrame,
        safeTop: safeTop, auxiliaryTopLeftArea: coreRect(screen.auxiliaryTopLeftArea),
        auxiliaryTopRightArea: coreRect(screen.auxiliaryTopRightArea), isBuiltIn: isBuiltIn,
        width: preferences.width, height: panelHeight, horizontalNudge: preferences.horizontalNudge)
    else { return nil }
    let frame = CGRect(
      x: placement.frame.x, y: placement.frame.y, width: placement.frame.width,
      height: placement.frame.height)
    return (placement, frame, viewportSize)
  }

  @discardableResult func updateCameraDockPlacement(
    on screen: NSScreen, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    let priorSize = viewportSize
    guard applyCameraDockPresentation(on: screen, preferences: preferences, style: style) else {
      return false
    }
    if priorSize != viewportSize { operatorController?.cameraDockResized(to: viewportSize) }
    return true
  }

  @discardableResult func updateCameraDockPresentation(style: ReadingStyle) -> CGSize? {
    guard isCameraDock, let screen = window?.screen,
      applyCameraDockPresentation(on: screen, preferences: dockPreferences, style: style)
    else { return nil }
    return viewportSize
  }

  private func applyCameraDockPresentation(
    on screen: NSScreen, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    guard isCameraDock, let window,
      let geometry = Self.cameraDockGeometry(screen: screen, preferences: preferences, style: style)
    else { return false }
    dockPreferences = preferences.normalized()
    dockLocation = geometry.placement.location
    displayID = DisplayDescriptor.all().first { $0.screen == screen }?.id
    displayUUID =
      DisplayDescriptor.all().first { $0.screen == screen }?.preference.uuid
      ?? screen.localizedName
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
    if let screen = window?.screen {
      displayID = DisplayDescriptor.all().first { $0.screen == screen }?.id
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
    let content = NSHostingView(
      rootView: placement == .cameraDock
        ? AnyView(CameraDockGrip(state: controller.state, controller: controller))
        : AnyView(FloatingGrip(state: controller.state, controller: controller)))
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

struct CameraDockGrip: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController

  private var canPlay: Bool {
    !controller.script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 8) {
      Button {
        controller.hideOutput()
      } label: {
        Image(systemName: "xmark")
      }
      .help("Return to the previous presentation surface · Escape")
      .accessibilityLabel("Close Camera Dock")

      Button {
        controller.toggle()
      } label: {
        Label(
          state.running ? "Pause" : "Play", systemImage: state.running ? "pause.fill" : "play.fill"
        )
        .labelStyle(.iconOnly)
      }
      .disabled(!canPlay)
      .help("Play or pause · Space")
      .accessibilityLabel("Play or pause")

      Text(statusText)
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Spacer(minLength: 4)

      Menu {
        Stepper(
          "Width · \(Int(state.cameraDockWidth.rounded())) pt",
          value: Binding(
            get: { Int(state.cameraDockWidth.rounded()) },
            set: { controller.setCameraDockWidth(Double($0)) }),
          in: 360...760, step: 20)
        Stepper(
          "Visible lines · \(state.cameraDockLineCount)",
          value: Binding(
            get: { state.cameraDockLineCount },
            set: { controller.setCameraDockLineCount($0) }),
          in: 2...5)
        Stepper(
          "Horizontal nudge · \(Int(state.cameraDockHorizontalNudge.rounded())) pt",
          value: Binding(
            get: { Int(state.cameraDockHorizontalNudge.rounded()) },
            set: { controller.setCameraDockHorizontalNudge(Double($0)) }),
          in: -120...120, step: 8)
        Button("Reset Placement") { controller.resetCameraDockPreferences() }
      } label: {
        Image(systemName: "slider.horizontal.3")
      }
      .help("Adjust Camera Dock width, visible lines, and horizontal position")
      .accessibilityLabel("Adjust Camera Dock")
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .frame(height: 40)
    .padding(.horizontal, 6)
    .foregroundStyle(.primary)
  }

  private var statusText: String {
    if controller.cameraDockCameraMayBeElsewhere {
      let status = state.running ? "Playing" : "Paused"
      return "\(status) · camera may be on another display"
    }
    if state.voiceActive && !state.voiceMessage.isEmpty { return state.voiceMessage }
    if state.running { return "Playing" }
    return controller.session.state == .idle ? "Ready" : "Paused · Space to resume"
  }
}
