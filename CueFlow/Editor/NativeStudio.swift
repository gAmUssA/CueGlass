import AppKit
import CueFlowCore
import SwiftUI

@MainActor final class TakeReadout: ObservableObject {
  @Published var elapsed = "00:00"
  @Published var remaining = "—"
  @Published var pace = "30 lpm"
  @Published var wpm = "≈ — wpm"
  @Published var status = "Ready"
  @Published var progress = 0.0
}
@MainActor final class ActionButton: NSButton {
  var playbackCommand: PlaybackCommand?
  var invoke: (() -> Void)?
  convenience init(symbol: String, label: String, action: @escaping () -> Void) {
    self.init(frame: .zero)
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    title = ""
    bezelStyle = .texturedRounded
    refusesFirstResponder = true
    toolTip = label
    setAccessibilityLabel(label)
    target = self
    self.action = #selector(fire)
    invoke = action
    setButtonType(.momentaryPushIn)
  }
  @objc private func fire() { invoke?() }
}
struct StageReadout: View {
  @ObservedObject var readout: TakeReadout
  var body: some View {
    HStack(spacing: 12) {
      Text(readout.status).font(.caption.weight(.semibold)).padding(6).background(
        .white.opacity(0.08), in: Capsule())
      Text(readout.elapsed).monospacedDigit()
      ProgressView(value: readout.progress).tint(.gray)
      Text(readout.remaining).monospacedDigit()
      VStack(alignment: .trailing) {
        Text(readout.pace).font(.headline)
        Text(readout.wpm).font(.caption2)
      }
    }.foregroundStyle(.white).padding(12).frame(height: 56).background(Color(white: 0.12))
  }
}
struct StageFooter: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "tortoise")
        Slider(
          value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          in: 2...max(10, state.maximum)
        ).tint(.gray).accessibilityLabel("Reading pace in lines per minute")
        Image(systemName: "hare")
        TextField(
          "LPM", value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          format: .number.precision(.fractionLength(1))
        ).frame(width: 52)
      }
      HStack {
        Text(state.status).font(.caption).lineLimit(2)
        Spacer()
        if state.pending {
          Button("Load Latest") { controller.loadLatest() }.disabled(state.running)
        }
      }
      Text(
        "↑ ↓ \(Int(state.fineStep)) lpm · ⇧↑ ⇧↓ \(Int(state.jumpStep)) lpm · Scroll to pause and scrub"
      ).font(.caption2).foregroundStyle(
        .secondary)
    }.foregroundStyle(.white).padding(12).background(Color(white: 0.09))
  }
}
@MainActor enum CommandRouter {
  static var map = CommandMap()
  static func chord(_ event: NSEvent) -> KeyChord {
    let keys: [UInt16: String] = [
      49: "space", 126: "up", 125: "down", 123: "left", 124: "right", 116: "pageup",
      121: "pagedown", 115: "home", 53: "escape",
    ]
    var key = keys[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
    if let special = event.specialKey {
      switch special {
      case .upArrow: key = "up"
      case .downArrow: key = "down"
      case .leftArrow: key = "left"
      case .rightArrow: key = "right"
      case .pageUp: key = "pageup"
      case .pageDown: key = "pagedown"
      case .home: key = "home"
      default: break
      }
    }
    let flags = event.modifierFlags
    return KeyChord(
      key, shift: flags.contains(.shift), command: flags.contains(.command),
      option: flags.contains(.option), control: flags.contains(.control))
  }
  static func route(_ event: NSEvent, window: NSWindow, controller: OperatorWindowController?)
    -> Bool
  {
    guard let controller else { return false }
    let chord = chord(event)
    if chord.key == "escape", controller.output != nil || controller.floating != nil {
      controller.hideOutput()
      return true
    }
    guard OperatorWindow.acceptsTransport(window.firstResponder),
      let command = map.command(for: chord)
    else { return false }
    controller.execute(command)
    return true
  }
  static func load() {
    guard let data = UserDefaults.standard.data(forKey: "commandMap") else { return }
    do { map = try CommandMap.decode(data) } catch let error as NSError {
      NSApp.presentError(error)
    }
  }
  static func save() throws {
    let data = try JSONEncoder().encode(map)
    if ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1" {
      UserDefaults.standard.set(data, forKey: "commandMap")
    }
  }
}

extension FrameClamp {
  static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
    let value = clamp(
      Rect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
      to: Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height))
    return CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
  }
}
