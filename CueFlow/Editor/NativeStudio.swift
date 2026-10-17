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
    HStack(spacing: 16) {
      HStack(spacing: 6) {
        Circle().fill(statusColor)
          .frame(width: 5, height: 5)
        Text(readout.status).font(.system(size: 11, weight: .semibold))
      }.padding(.horizontal, 8).padding(.vertical, 5).background(
        statusColor.opacity(0.12), in: Capsule())
      clock(readout.elapsed, label: "elapsed")
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.12))
          Capsule().fill(.white.opacity(0.65))
            .frame(width: geometry.size.width * min(1, max(0, readout.progress)))
        }
      }.frame(minWidth: 100, idealWidth: 140, maxWidth: 200).frame(height: 3)
      clock(readout.remaining == "—" ? "—" : "−" + readout.remaining, label: "remaining")
      VStack(alignment: .trailing, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(readout.pace.replacingOccurrences(of: " lpm", with: "")).font(
            .system(size: 17, weight: .semibold))
          Text("lpm").font(.system(size: 11))
        }.monospacedDigit()
        if !readout.wpm.contains("—") {
          Text(readout.wpm).font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
    }.padding(.horizontal, 16).frame(height: 56).foregroundStyle(.primary).background(
      Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255)
    ).environment(\.colorScheme, .dark)
  }
  private var statusColor: Color {
    if readout.status == "Playing" { return .green }
    if readout.status == "Paused" || readout.status.hasPrefix("Starting") { return .orange }
    if readout.status == "End of script" { return .blue }
    return .secondary
  }
  private func clock(_ value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
      Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
    }.fixedSize()
  }
}
/// Pale notice over the page while a take holds it read-only (Quiet Studio ①/④).
struct EditorTakeBanner: View {
  unowned let controller: OperatorWindowController
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary)
      Text("Editing locked during the take").font(.system(size: 12)).lineLimit(1)
      Spacer(minLength: 8)
      Button("Stop Take") { controller.stop() }.controlSize(.small)
    }
    .padding(.horizontal, 16).padding(.vertical, 8)
    .background(Color(nsColor: .systemYellow).opacity(0.12))
    .overlay(alignment: .bottom) { Divider() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Editing locked during the take")
  }
}
struct StageFooter: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text("Speed").font(.system(size: 11))
        Image(systemName: "tortoise").foregroundStyle(.secondary)
        Slider(
          value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          in: 2...max(10, state.maximum)
        ).accessibilityLabel("Reading pace in lines per minute")
        Image(systemName: "hare").foregroundStyle(.secondary)
        TextField(
          "LPM", value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          format: .number.precision(.fractionLength(1))
        ).textFieldStyle(.roundedBorder).frame(width: 54)
        Text("lpm").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      if state.active && state.voiceActive {
        HStack(spacing: 8) {
          Circle().fill(state.voiceSuspended ? .orange : .green).frame(width: 6, height: 6)
          Text(state.voiceMessage).font(.system(size: 11)).lineLimit(1)
          Spacer(minLength: 0)
          if state.voiceSuspended {
            Button("Resume Following") { controller.startVoiceFollow(resume: true) }
              .controlSize(.small)
          }
          Button(state.voiceSuspended ? "Stop Following" : "Stop Follow Voice") {
            controller.stopVoiceFollow()
          }.controlSize(.small)
        }.padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
      }
      if state.pending
        || !["", "Ready", "Paused", "Playing", "Take prepared", "Stopped — editing enabled"]
          .contains(state.status)
      {
        // Notices are inline banners, not alerts (Quiet Studio ⑥).
        HStack(alignment: .center, spacing: 10) {
          Image(systemName: state.pending ? "info.circle" : "exclamationmark.circle")
            .foregroundStyle(.secondary)
          if state.pending {
            VStack(alignment: .leading, spacing: 2) {
              Text("A newer version of this script is available.").font(.system(size: 12))
              Text("The current take is unchanged until you load it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
          } else {
            Text(state.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
          }
          Spacer()
          if state.pending {
            Button("Load") { controller.loadLatest() }.disabled(state.running)
              .accessibilityLabel("Load Latest")
          } else if state.active && !state.running {
            Button(
              controller.session.message.localizedCaseInsensitiveContains("end")
                ? "Restart" : "Resume"
            ) {
              if controller.session.message.localizedCaseInsensitiveContains("end") {
                controller.restart()
              } else {
                controller.toggle()
              }
            }.controlSize(.small)
          }
        }.padding(10).background(
          RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1))))
      }
      Text(
        "↑ ↓ fine \(Int(state.fineStep)) lpm · ⇧↑ ⇧↓ jump \(Int(state.jumpStep)) lpm · scroll over stage to scrub (pauses)"
      )
      .font(.system(size: 10)).foregroundStyle(.tertiary)
    }.padding(16).foregroundStyle(.primary).environment(\.colorScheme, .dark)
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

@MainActor final class StudioSurface: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor(srgbRed: 22.0 / 255, green: 22.0 / 255, blue: 24.0 / 255, alpha: 1).setFill()
    dirtyRect.fill()
  }
}

@MainActor final class EditorDecoration: NSView {
  weak var editor: DropEditor?
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) { editor?.drawDecorations(dirtyRect) }
}
