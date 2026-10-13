import AppKit
import CueFlowCore

@MainActor struct DisplayDescriptor {
  let screen: NSScreen
  let preference: DisplayPreference
  let id: CGDirectDisplayID
  static func all() -> [Self] {
    NSScreen.screens.compactMap { screen in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      let id = number.uint32Value
      let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
        CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
      }
      return Self(screen: screen, preference: .init(uuid: uuid, name: screen.localizedName), id: id)
    }
  }
}
@MainActor final class OutputWindow: NSWindow {
  var exit: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { exit?() } else { super.keyDown(with: event) }
  }
}
@MainActor final class OutputWindowController: NSWindowController, NSWindowDelegate {
  let reflection = ReflectionContainerView(frame: .zero)
  let displayID: CGDirectDisplayID
  var onClose: (() -> Void)?
  init(display: DisplayDescriptor) {
    displayID = display.id
    let window = OutputWindow(
      contentRect: display.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false,
      screen: display.screen)
    super.init(window: window)
    window.isReleasedWhenClosed = false
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
    window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    window.ignoresMouseEvents = true
    window.contentView = reflection
    window.setFrame(display.screen.frame, display: true)
    window.delegate = self
    window.exit = { [weak self] in self?.close() }
  }
  required init?(coder: NSCoder) { fatalError("Use init(display:)") }
  func windowWillClose(_ notification: Notification) {
    reflection.viewport.driver?.stop()
    onClose?()
  }
}
