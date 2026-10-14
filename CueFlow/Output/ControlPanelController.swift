import AppKit
import CueFlowCore
import SwiftUI

@MainActor final class ControlPanelController: NSWindowController {
  var transportButtons: [ActionButton] = []
  weak var playButton: NSButton?
  weak var operatorController: OperatorWindowController?
  init(controller: OperatorWindowController) {
    operatorController = controller
    let panel = PresentationPanel(
      contentRect: CGRect(x: 150, y: 150, width: 420, height: 124),
      styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
      backing: .buffered, defer: false)
    super.init(window: panel)
    panel.title = "Controls"
    panel.operatorController = controller
    panel.hidesOnDeactivate = false
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = false
    let material = NSVisualEffectView()
    material.appearance = NSAppearance(named: .darkAqua)
    material.material = .hudWindow
    material.blendingMode = .behindWindow
    material.state = .active
    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
      material.wantsLayer = true
      material.layer?.backgroundColor =
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor
    }
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    material.addSubview(stack)
    let row = NSStackView()
    row.spacing = 5
    for (symbol, label, command) in [
      ("backward.end.fill", "Restart · Home", PlaybackCommand.restart),
      ("chevron.up", "Previous paragraph · Page Up", .previousParagraph),
      ("play.fill", "Play or pause · Space", .toggle),
      ("chevron.down", "Next paragraph · Page Down", .nextParagraph),
      ("arrow.up.arrow.down", "Reverse direction · R", .reverse),
    ] {
      let button = ActionButton(symbol: symbol, label: label) { [weak controller] in
        controller?.execute(command)
      }
      button.playbackCommand = command
      transportButtons.append(button)
      button.widthAnchor.constraint(equalToConstant: command == .toggle ? 36 : 26).isActive = true
      button.heightAnchor.constraint(equalToConstant: command == .toggle ? 36 : 24).isActive = true
      if command == .toggle {
        playButton = button
        button.bezelStyle = .circular
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
      }
      row.addArrangedSubview(button)
    }
    let timer = NSHostingView(rootView: PanelTimer(readout: controller.readout))
    row.addArrangedSubview(timer)
    row.addArrangedSubview(
      ActionButton(symbol: "macwindow", label: "Show Operator Window") { [weak controller] in
        controller?.window?.makeKeyAndOrderFront(nil)
      })
    stack.addArrangedSubview(row)
    let speed = NSHostingView(
      rootView: PanelPace(
        state: controller.state, readout: controller.readout, controller: controller))
    stack.addArrangedSubview(speed)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: material.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: material.bottomAnchor, constant: -8),
    ])
    panel.contentView = material
  }
  required init?(coder: NSCoder) { fatalError("Use init(controller:)") }
  func placeSafely() {
    guard let controller = operatorController, let window else { return }
    let outputScreen = controller.output?.window?.screen
    guard let safe = NSScreen.screens.first(where: { $0 != outputScreen }) else {
      window.orderOut(nil)
      return
    }
    window.setFrame(FrameClamp.clamp(window.frame, to: safe.visibleFrame), display: true)
    if window.screen == outputScreen && outputScreen != nil {
      window.orderOut(nil)
    } else {
      window.orderFront(nil)
    }
  }
}
struct PanelTimer: View {
  @ObservedObject var readout: TakeReadout
  var body: some View {
    VStack {
      Text(readout.elapsed).monospacedDigit().font(.system(size: 15, weight: .semibold))
      Text(readout.remaining + " left").font(.caption2)
    }.frame(minWidth: 76)
  }
}
struct PanelPace: View {
  @ObservedObject var state: OperatorState
  @ObservedObject var readout: TakeReadout
  unowned let controller: OperatorWindowController
  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        ForEach([0, 1], id: \.self) { index in
          let step = index == 0 ? -state.jumpStep : -state.fineStep
          Button("\(Int(step))") { controller.adjustSpeed(step) }.buttonStyle(.borderless)
            .focusable(false).frame(minWidth: 24, minHeight: 24)
        }
        Slider(
          value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          in: 2...state.maximum
        ).tint(.gray).accessibilityLabel("Reading pace")
          .focusable(false)
        ForEach([0, 1], id: \.self) { index in
          let step = index == 0 ? state.fineStep : state.jumpStep
          Button("+\(Int(step))") { controller.adjustSpeed(step) }.buttonStyle(.borderless)
            .focusable(false).frame(minWidth: 24, minHeight: 24)
        }
      }
      Text(readout.pace + (readout.wpm.contains("—") ? "" : " · " + readout.wpm)).font(.caption)
    }
  }
}
