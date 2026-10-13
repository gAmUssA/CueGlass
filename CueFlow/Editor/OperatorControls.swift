import AppKit
import CueFlowCore
import SwiftUI

struct OperatorControls: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  private func styleBinding<T>(_ path: WritableKeyPath<ReadingStyle, T>) -> Binding<T> {
    Binding(
      get: { state.style[keyPath: path] },
      set: { value in
        var style = state.style
        style[keyPath: path] = value
        controller.changeStyle(style)
      })
  }
  private func colorBinding(_ path: WritableKeyPath<ReadingStyle, [Double]>) -> Binding<Color> {
    Binding(
      get: { Color(nsColor: PresentationBuilder.color(state.style[keyPath: path])) },
      set: { value in
        guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
        var style = state.style
        style[keyPath: path] = [
          color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent,
        ]
        controller.changeStyle(style)
      })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button(state.running ? "Pause" : "Play") { controller.toggle() }.accessibilityLabel(
          "Play or pause")
        Button("Stop Take") { controller.stop() }
        Button("Restart") { controller.restart() }
        Button("Load Latest") { controller.loadLatest() }.disabled(!state.pending || state.running)
        Text("Speed")
        Slider(value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }), in: 1...300)
          .accessibilityLabel("Scroll speed").frame(maxWidth: 180)
        TextField(
          "Speed", value: Binding(get: { state.speed }, set: { controller.setSpeed($0) }),
          format: .number.precision(.fractionLength(1))
        ).frame(width: 65).accessibilityLabel("Speed in points per second")
        Stepper(
          "pt/s", onIncrement: { controller.adjustSpeed(1) },
          onDecrement: { controller.adjustSpeed(-1) })
      }
      HStack {
        Picker("Style", selection: styleBinding(\.mode)) {
          Text("Normalized").tag(ReadingStyle.Mode.normalized)
          Text("Preserve Source").tag(ReadingStyle.Mode.preserveSource)
        }.frame(width: 230)
        Picker(
          "Font",
          selection: Binding(
            get: { state.style.fontIdentifier ?? "" },
            set: { name in
              var style = state.style
              style.fontIdentifier = name.isEmpty ? nil : name
              controller.changeStyle(style)
            })
        ) {
          Text("System").tag("")
          ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) {
            Text($0).tag($0)
          }
        }.frame(width: 240)
        Text("Size")
        Slider(value: styleBinding(\.fontSize), in: 18...180).frame(width: 150).accessibilityLabel(
          "Presentation font size")
        TextField("Size", value: styleBinding(\.fontSize), format: .number).frame(width: 60)
      }
      HStack {
        Text("Line height")
        Slider(value: styleBinding(\.lineHeightMultiplier), in: 1...2).frame(width: 100)
          .accessibilityLabel("Line height")
        Text("Spacing")
        Slider(value: styleBinding(\.paragraphSpacing), in: 0...200).frame(width: 100)
          .accessibilityLabel("Paragraph spacing")
        Text("Column")
        Slider(value: styleBinding(\.columnWidthFraction), in: 0.25...1).frame(width: 100)
          .accessibilityLabel("Column width")
        Text("Guide")
        Slider(value: styleBinding(\.readingGuideFraction), in: 0...1).frame(width: 100)
          .accessibilityLabel("Reading guide position")
        Toggle("Show guide", isOn: styleBinding(\.showsReadingGuide))
      }
      HStack {
        Picker("Output", selection: $state.selectedDisplay) {
          ForEach(state.displays, id: \.self) { key in Text(controller.displayName(key)).tag(key) }
        }.frame(width: 310)
        Button(controller.output == nil ? "Show Output" : "Stop Output") { controller.showOutput() }
        Toggle("Horizontal", isOn: $state.horizontal).onChange(of: state.horizontal) {
          controller.reflect()
        }
        Toggle("Vertical", isOn: $state.vertical).onChange(of: state.vertical) {
          controller.reflect()
        }
        Toggle("Show as output", isOn: $state.calibrated).onChange(of: state.calibrated) {
          controller.reflect()
        }
        Button("Calibration") { controller.calibration() }
      }
      HStack {
        ColorPicker("Text", selection: colorBinding(\.foregroundRGBA)).frame(width: 110)
        ColorPicker("Background", selection: colorBinding(\.backgroundRGBA)).frame(width: 160)
        Button("Save On This Mac…") { controller.script.save(nil) }
        Button("Save to iCloud…") { controller.saveICloud() }
        Button("Save a Copy…") { controller.script.saveTo(nil) }
        Button("Browse Versions…") { controller.script.browseVersions(nil) }
        Button("Download") { controller.requestDownload() }
        Button("Refresh Status") { Task { await controller.script.refreshCloudStatus() } }
      }
      Text(state.status).font(.callout).lineLimit(2).accessibilityLabel("Transport status")
      Text(state.cloud).font(.caption).foregroundStyle(.secondary).accessibilityLabel(
        "Storage status")
    }.padding(12)
  }
}
