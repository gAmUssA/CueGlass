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
@MainActor final class FloatingPrompterWindowController: NSWindowController, NSWindowDelegate {
  let reflection = ReflectionContainerView(frame: .zero)
  var onClose: (() -> Void)?
  var root: FloatingRoot?
  var displayID: CGDirectDisplayID?
  weak var operatorController: OperatorWindowController?
  init(screen: NSScreen, controller: OperatorWindowController) {
    operatorController = controller
    displayID = DisplayDescriptor.all().first { $0.screen == screen }?.id
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
    window.operatorController = controller
    window.title = "CueGlass · Floating Prompter"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.hidesOnDeactivate = false
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.minSize = CGSize(width: 320, height: 180)
    let root = FloatingRoot(reflection: reflection, controller: controller)
    self.root = root
    window.contentView = root
    window.delegate = self
    window.acceptsMouseMovedEvents = true
    reflection.wantsLayer = true
    reflection.layer?.cornerRadius = 14
    reflection.layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("Use init(screen:controller:)") }
  func windowDidEndLiveResize(_ notification: Notification) {
    operatorController?.floatingResized()
    saveFrame()
  }
  func windowDidMove(_ notification: Notification) { saveFrame() }
  func windowDidChangeScreen(_ notification: Notification) {
    if let screen = window?.screen {
      displayID = DisplayDescriptor.all().first { $0.screen == screen }?.id
    }
    saveFrame()
  }
  private func saveFrame() {
    guard ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1", let window,
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
  let grip: NSHostingView<FloatingGrip>
  weak var controller: OperatorWindowController?
  var logicalSize = CGSize(width: 800, height: 400) { didSet { needsLayout = true } }
  private var tracking: NSTrackingArea?
  init(reflection: ReflectionContainerView, controller: OperatorWindowController) {
    self.reflection = reflection
    self.controller = controller
    grip = NSHostingView(rootView: FloatingGrip(state: controller.state, controller: controller))
    super.init(frame: .zero)
    addSubview(reflection)
    addSubview(grip)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) { fatalError("Use init(reflection:controller:)") }
  override func layout() {
    super.layout()
    reflection.frame = bounds
    reflection.setBoundsSize(logicalSize)
    reflection.needsLayout = true
    grip.frame = CGRect(x: 0, y: max(0, bounds.height - 72), width: bounds.width, height: 72)
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
    if controller?.session.state != .running { grip.alphaValue = 1 }
  }
  override func mouseExited(with event: NSEvent) { grip.alphaValue = 0 }
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
          Image(systemName: "play.fill")
        }.accessibilityLabel("Resume · Space")
      }.buttonStyle(.borderless).padding(6)
      if !state.contrastWarning.isEmpty { Text(state.contrastWarning).font(.caption2).lineLimit(2) }
    }.foregroundStyle(.white).background(.black.opacity(0.75)).clipShape(
      RoundedRectangle(cornerRadius: 8))
  }
}
