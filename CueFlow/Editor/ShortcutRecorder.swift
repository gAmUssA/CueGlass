import AppKit
import CueFlowCore

@MainActor final class ShortcutRecorder: NSView {
  var capture: ((KeyChord) -> Void)?
  override var acceptsFirstResponder: Bool { true }
  override func keyDown(with event: NSEvent) { capture?(CommandRouter.chord(event)) }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    capture?(CommandRouter.chord(event))
    return true
  }
  override func draw(_ dirtyRect: NSRect) {
    "Press the new key combination".draw(
      at: NSPoint(x: 24, y: 40),
      withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor])
  }
}
extension OperatorWindowController {
  func otherFonts() {
    NSFontManager.shared.target = self
    NSFontManager.shared.setSelectedFont(PresentationFont.resolve(state.style), isMultiple: false)
    NSFontManager.shared.orderFrontFontPanel(nil)
  }
  @objc func changeFont(_ sender: NSFontManager) {
    let font = sender.convert(PresentationFont.resolve(state.style))
    var style = state.style
    style.fontIdentifier = font.fontName
    style.fontSize = font.pointSize
    changeStyle(style)
  }
  func recordShortcut(_ command: PlaybackCommand) {
    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 340, height: 100), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    panel.title = "Shortcut · \(command.rawValue)"
    panel.isReleasedWhenClosed = false
    let recorder = ShortcutRecorder(frame: panel.contentView?.bounds ?? .zero)
    panel.contentView = recorder
    recorder.capture = { [weak self, weak panel] chord in
      guard let self else { return }
      do {
        try CommandRouter.map.bind(chord, to: command)
        try CommandRouter.save()
        if let panel {
          self.window?.endSheet(panel)
          panel.close()
        }
        self.refresh()
        self.state.status = "Shortcut saved: \(chord.label)"
      } catch let error as NSError {
        self.state.status =
          "Shortcut conflicts with another command or a reserved Mac shortcut (\(error.code)). Choose another key."
      }
    }
    if let window { window.beginSheet(panel) } else { panel.makeKeyAndOrderFront(nil) }
    panel.makeFirstResponder(recorder)
  }
  func saveOperatorPreferences() {
    guard ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" else { return }
    UserDefaults.standard.set(state.fineStep, forKey: "fineStep")
    UserDefaults.standard.set(state.jumpStep, forKey: "jumpStep")
    UserDefaults.standard.set(state.maximum, forKey: "maximumLPM")
    UserDefaults.standard.set(state.countdown, forKey: "countdown")
    UserDefaults.standard.set(state.hideControls, forKey: "hideControls")
    UserDefaults.standard.set(state.floatingOpacity, forKey: "floatingOpacity")
    UserDefaults.standard.set(state.clickThrough, forKey: "clickThrough")
    UserDefaults.standard.set(state.overFullScreen, forKey: "overFullScreen")
  }
}
