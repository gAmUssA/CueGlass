import AppKit
import CueFlowCore
import SwiftUI

struct OperatorControls: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  @State private var selectedCommand = PlaybackCommand.toggle
  @AppStorage("layoutExpanded") private var layoutExpanded = false
  @AppStorage("colorsExpanded") private var colorsExpanded = false
  @AppStorage("timingExpanded") private var timingExpanded = false
  @AppStorage("keysExpanded") private var keysExpanded = false
  @AppStorage("floatingExpanded") private var floatingExpanded = false
  private func binding<T>(_ path: WritableKeyPath<ReadingStyle, T>) -> Binding<T> {
    Binding(
      get: { state.style[keyPath: path] },
      set: { value in
        var style = state.style
        style[keyPath: path] = value
        controller.changeStyle(style)
      })
  }
  private func color(_ path: WritableKeyPath<ReadingStyle, [Double]>) -> Binding<Color> {
    Binding(
      get: { Color(nsColor: PresentationBuilder.color(state.style[keyPath: path])) },
      set: { value in
        guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
        var style = state.style
        style[keyPath: path] = [
          c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent,
        ]
        controller.changeStyle(style)
      })
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        InspectorSection("Text") {
          Picker(
            "Font",
            selection: Binding(
              get: {
                state.style.fontIdentifier
                  ?? (state.style.systemDesign == .serif ? "serif" : "system")
              },
              set: { value in
                var style = state.style
                style.fontIdentifier = ["system", "serif"].contains(value) ? nil : value
                style.systemDesign = value == "serif" ? .serif : .default
                controller.changeStyle(style)
              })
          ) {
            Text("Studio Sans · System").tag("system")
            Text("Manuscript · Serif").tag("serif")
            Text("Charter").tag("Charter")
            Text("Iowan").tag("IowanOldStyle-Roman")
            Text("Avenir").tag("AvenirNext-DemiBold")
            if let name = state.style.fontIdentifier,
              !["Charter", "IowanOldStyle-Roman", "AvenirNext-DemiBold"].contains(name)
            {
              Text(name).tag(name)
            }
          }.disabled(state.style.mode == .preserveSource)
          Button("Other Fonts…") { controller.otherFonts() }.disabled(
            state.style.mode == .preserveSource)
          Picker("Weight", selection: binding(\.fontWeight)) {
            ForEach(ReadingStyle.Weight.allCases, id: \.self) {
              Text($0.rawValue.capitalized).tag($0)
            }
          }.disabled(state.style.mode == .preserveSource)
          if state.style.mode == .preserveSource {
            Text("Source fonts and emphasis are retained; Size scales the source.").font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack {
            Text("Size")
            Spacer()
            TextField("Size", value: binding(\.fontSize), format: .number).labelsHidden().frame(
              width: 54)
            Text("pt").foregroundStyle(.secondary)
          }.frame(height: 28)
          valueSlider("Line height", path: \.lineHeightMultiplier, range: 1...2)
        }
        InspectorSection("Reading Guide") {
          Picker(
            "Style",
            selection: Binding(
              get: {
                state.style.showsReadingGuide ? state.style.readingGuideStyle.rawValue : "off"
              },
              set: { value in
                var style = state.style
                style.showsReadingGuide = value != "off"
                if let guide = ReadingStyle.GuideStyle(rawValue: value) {
                  style.readingGuideStyle = guide
                }
                controller.changeStyle(style)
              })
          ) {
            Text("Line").tag(ReadingStyle.GuideStyle.line.rawValue)
            Text("Triangle").tag(ReadingStyle.GuideStyle.triangle.rawValue)
            Text("Both").tag(ReadingStyle.GuideStyle.triangleAndLine.rawValue)
            Text("Off").tag("off")
          }.pickerStyle(.segmented).labelsHidden().frame(height: 28)
          valueSlider("Position", path: \.readingGuideFraction, range: 0...1)
          valueSlider("Guide opacity", path: \.readingGuideOpacity, range: 0...1)
          valueSlider("Edge fade", path: \.edgeFadeFraction, range: 0...0.3)
        }
        InspectorSection("Output") {
          Picker("Display", selection: $state.selectedDisplay) {
            ForEach(state.displays, id: \.self) { key in Text(controller.displayName(key)).tag(key)
            }
          }
          Toggle("Reflect horizontally", isOn: $state.horizontal).onChange(of: state.horizontal) {
            controller.reflect()
          }
          Toggle("Reflect vertically", isOn: $state.vertical).onChange(of: state.vertical) {
            controller.reflect()
          }
          Toggle("Preview as output", isOn: $state.calibrated).onChange(of: state.calibrated) {
            controller.reflect()
          }
          Button("Calibration Pattern…") { controller.calibration() }
          DisclosureGroup("Floating Window", isExpanded: $floatingExpanded) {
            Slider(value: $state.floatingOpacity, in: 0.3...1).onChange(of: state.floatingOpacity) {
              controller.updateFloatingOptions()
              controller.saveOperatorPreferences()
            }.accessibilityLabel("Whole floating window opacity")
            Text("Whole window: \(Int(state.floatingOpacity*100))%").font(.caption)
            Toggle("Over full-screen apps", isOn: $state.overFullScreen).onChange(
              of: state.overFullScreen
            ) {
              controller.updateFloatingOptions()
              controller.saveOperatorPreferences()
            }
            Toggle("Click-through while playing", isOn: $state.clickThrough).onChange(
              of: state.clickThrough
            ) {
              controller.refresh()
              controller.saveOperatorPreferences()
            }
            if !state.contrastWarning.isEmpty { Text(state.contrastWarning).font(.caption) }
          }

        }
        DisclosureGroup("Layout", isExpanded: $layoutExpanded) {
          Picker("Typography", selection: binding(\.mode)) {
            Text("Normalized").tag(ReadingStyle.Mode.normalized)
            Text("Preserve Source").tag(ReadingStyle.Mode.preserveSource)
          }
          valueSlider("Column width", path: \.columnWidthFraction, range: 0.25...1)
          valueSlider("Side margins", path: \.sideMarginFraction, range: 0...0.25)
          valueSlider("Paragraph spacing", path: \.paragraphSpacing, range: 0...200)
        }
        DisclosureGroup("Colors", isExpanded: $colorsExpanded) {
          ColorPicker("Text", selection: color(\.foregroundRGBA))
          ColorPicker("Background", selection: color(\.backgroundRGBA))
          valueSlider("Text panel opacity", path: \.textPanelOpacity, range: 0...1)
          if !state.contrastWarning.isEmpty {
            Text(state.contrastWarning).font(.caption).foregroundStyle(.secondary)
          }
        }
        DisclosureGroup("Timing", isExpanded: $timingExpanded) {
          Picker("Start countdown", selection: $state.countdown) {
            Text("Off").tag(0)
            ForEach([3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
          }
          TextField("Finish in seconds", value: $state.duration, format: .number)
          Button("Enable Timed Scrolling") {
            controller.perform {
              if controller.session.state == .idle {
                try controller.session.prepare(controller.script)
                controller.render()
              }
              try controller.session.enableTimed(seconds: state.duration)
              controller.refresh()
            }
          }
          Toggle("Hide controls while playing", isOn: $state.hideControls)
        }
        DisclosureGroup("Controls & Keys", isExpanded: $keysExpanded) {
          Text("App must be frontmost, or the clicker must target CueGlass. No global monitoring.")
            .font(.caption)
          Picker("Command", selection: $selectedCommand) {
            ForEach(PlaybackCommand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          Text(
            CommandRouter.map.bindings.filter { $0.command == selectedCommand }.map {
              $0.chord.label
            }
            .joined(separator: " · ")
          ).font(.caption)
          Button("Record Shortcut…") { controller.recordShortcut(selectedCommand) }
          Button("Reset Defaults") {
            CommandRouter.map = CommandMap()
            controller.perform {
              try CommandRouter.save()
              controller.refresh()
              state.status = "Default shortcuts restored"
            }
          }
          Slider(value: $state.maximum, in: 10...240, step: 1).onChange(of: state.maximum) {
            controller.session.configuredMax = state.maximum
            controller.perform {
              try controller.session.updateLayout(
                end: controller.session.timeline.upperBound,
                paragraphs: controller.session.paragraphPositions,
                wordCount: controller.session.words, lineCount: controller.session.lines)
            }
            controller.saveOperatorPreferences()
          }.accessibilityLabel("Maximum lines per minute")
          Text("Maximum \(Int(state.maximum)) lpm").font(.caption)
          Stepper("Fine step \(Int(state.fineStep)) lpm", value: $state.fineStep, in: 1...10)
            .onChange(of: state.fineStep) { controller.saveOperatorPreferences() }
          Stepper("Jump step \(Int(state.jumpStep)) lpm", value: $state.jumpStep, in: 1...60)
            .onChange(of: state.jumpStep) { controller.saveOperatorPreferences() }
        }
      }.padding(14)
    }.environment(\.colorScheme, state.darkAppearance ? .dark : .light).font(.system(size: 13))
      .controlSize(.small).tint(.gray).onChange(of: state.countdown) {
        controller.saveOperatorPreferences()
      }.onChange(of: state.hideControls) { controller.saveOperatorPreferences() }
  }
  private func sliderValue(_ path: WritableKeyPath<ReadingStyle, Double>) -> String {
    let value = state.style[keyPath: path]
    if path == \.lineHeightMultiplier { return String(format: "%.2f×", value) }
    if path == \.paragraphSpacing { return String(format: "%.0f pt", value) }
    return String(format: "%.0f%%", value * 100)
  }
  private func valueSlider(
    _ label: String, path: WritableKeyPath<ReadingStyle, Double>, range: ClosedRange<Double>
  ) -> some View {
    HStack(spacing: 8) {
      Text(label).frame(width: 88, alignment: .leading)
      Slider(value: binding(path), in: range).accessibilityLabel(label)
      Text(sliderValue(path))
        .foregroundStyle(.secondary).monospacedDigit()
    }.frame(height: 28)
  }
}

private struct InspectorSection<Content: View>: View {
  let title: String
  let content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
        .tracking(0.8).foregroundStyle(.secondary)
      content
      Divider().padding(.top, 4)
    }
  }
}
