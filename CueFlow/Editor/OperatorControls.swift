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
  @AppStorage("cameraDockExpanded") private var cameraDockExpanded = false
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
          Picker(
            "Surface",
            selection: Binding(
              get: { controller.selectedPresentationSurface },
              set: { controller.selectPresentationSurface($0) })
          ) {
            Text("Preview").tag("preview")
            Text("Display Output").tag("output")
            Text("Floating").tag("floating")
            Text(controller.cameraDockMenuTitle).tag("cameraDock")
          }
          Picker("Display", selection: $state.selectedDisplay) {
            if state.displays.isEmpty {
              Text("No display connected").tag(state.selectedDisplay)
            }
            ForEach(state.displays, id: \.self) { key in Text(controller.displayName(key)).tag(key)
            }
          }.disabled(state.displays.isEmpty)
          if controller.selectedPresentationSurface == "cameraDock" {
            if state.cameraDockFirstUseCalloutVisible {
              VStack(alignment: .leading, spacing: 8) {
                Text("Camera Dock is ready")
                  .font(.subheadline.weight(.semibold))
                Text(OperatorWindowController.cameraDockExplainer)
                  .font(.caption)
                  .fixedSize(horizontal: false, vertical: true)
                Button("Got it") { controller.acknowledgeCameraDockExplainer() }
                  .buttonStyle(.borderless)
              }
              .padding(10)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
              .accessibilityElement(children: .contain)
              .accessibilityLabel("Camera Dock first-use information")
            }
            Text(OperatorWindowController.cameraDockCaptureDisclosure)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if controller.cameraDock == nil {
            Toggle("Reflect horizontally", isOn: $state.horizontal).onChange(
              of: state.horizontal
            ) {
              controller.reflect()
            }
            Toggle("Reflect vertically", isOn: $state.vertical).onChange(of: state.vertical) {
              controller.reflect()
            }
            Toggle("Preview as output", isOn: $state.calibrated).onChange(
              of: state.calibrated
            ) {
              controller.reflect()
            }
            Button("Calibration Pattern…") { controller.calibration() }
          }
          DisclosureGroup("Camera Dock Placement", isExpanded: $cameraDockExpanded) {
            if let map = controller.cameraDockPlacementMap {
              CameraDockPlacementMapPreview(map: map)
                .aspectRatio(map.displayAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(Text(map.caption))
            } else {
              Text("Choose a display to preview Camera Dock placement.")
                .font(.caption).foregroundStyle(.secondary)
            }
            Slider(
              value: Binding(
                get: { state.cameraDockWidth },
                set: { controller.setCameraDockWidth($0) }),
              in: 360...760, step: 20
            )
            .accessibilityLabel("Camera Dock width")
            Text("Width · \(Int(state.cameraDockWidth.rounded())) pt").font(.caption)
            Stepper(
              "Visible lines · \(state.cameraDockLineCount)",
              value: Binding(
                get: { state.cameraDockLineCount },
                set: { controller.setCameraDockLineCount($0) }),
              in: 2...5)
            Slider(
              value: Binding(
                get: { state.cameraDockHorizontalNudge },
                set: { controller.setCameraDockHorizontalNudge($0) }),
              in: -120...120, step: 8
            )
            .accessibilityLabel("Camera Dock horizontal nudge")
            Text("Horizontal nudge · \(Int(state.cameraDockHorizontalNudge.rounded())) pt")
              .font(.caption)
            Toggle(
              "Notch island on displays without a notch",
              isOn: Binding(
                get: { state.cameraDockNotchIsland },
                set: { controller.setCameraDockNotchIsland($0) })
            )
            .accessibilityLabel("Notch island on displays without a notch")
            Button("Reset Placement") { controller.resetCameraDockPreferences() }
          }
          .onAppear { controller.setCameraDockPlacementPreviewExpanded(cameraDockExpanded) }
          .onChange(of: cameraDockExpanded) { _, expanded in
            controller.setCameraDockPlacementPreviewExpanded(expanded)
          }
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
            controller.enableTimedScrolling(seconds: state.duration)
          }
          Toggle("Hide controls while playing", isOn: $state.hideControls)
        }
        if state.voiceAvailable {
          InspectorSection("Follow Voice") {
            Picker(
              "Language",
              selection: Binding(
                get: { state.voiceLocale },
                set: { controller.selectVoiceLocale($0) })
            ) {
              ForEach(state.voiceLocales) { locale in
                Text(locale.displayName).tag(locale.identifier)
              }
            }
            .disabled(state.voiceLocales.isEmpty || state.voiceActive)
            .help("Choose a supported language. Selecting one does not open the microphone.")
            Picker(
              "Microphone",
              selection: Binding(
                get: {
                  state.voiceInputDevices.contains { $0.uid == state.voiceInputDevice }
                    ? state.voiceInputDevice : ""
                },
                set: { controller.selectVoiceInputDevice($0) })
            ) {
              Text("System Default").tag("")
              ForEach(state.voiceInputDevices) { device in
                Text(device.isDefault ? "\(device.name) (default)" : device.name).tag(device.uid)
              }
            }
            .help(
              "Choose which microphone Follow Voice listens to. Changing it while following moves capture to the new microphone without stopping the take."
            )
            .accessibilityLabel("Follow Voice microphone")
            Text(
              "English is the validated language. Other languages depend on the models available in macOS."
            )
            .font(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(
              "Speech is analyzed on this Mac. CueGlass does not record or save audio or transcript text."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(
              horizontal: false, vertical: true)
            Text("Scroll glide eases faster when confirmed speech moves through the script faster.")
              .font(.caption).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
            if Locale(identifier: state.voiceLocale).language.languageCode?.identifier == "en" {
              Text(
                "Say “CueGlass” or “Prompter”, then “pause”, “resume”, “stop” or “stop take”."
              )
              .font(.caption).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
              Text("CueGlass confirms commands after speech settles.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(
                  horizontal: false, vertical: true)
            } else {
              Text("Spoken transport commands currently require English.")
                .font(.caption).foregroundStyle(.secondary)
            }
            followVoiceControls
          }
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
            controller.session.suspendVoiceForManualControl("Maximum pace change")
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
  @ViewBuilder private var followVoiceControls: some View {
    if let voiceStatus {
      HStack(spacing: 6) {
        Image(systemName: voiceStatus.symbol)
        Text(voiceStatus.title)
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(voiceStatus.color)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(voiceStatus.color.opacity(0.12), in: Capsule())
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Follow Voice status: \(voiceStatus.title)")
    }
    switch state.voiceState {
    case .hidden:
      EmptyView()
    case .checking:
      ProgressView(state.voiceMessage).controlSize(.small)
    case .unavailable:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.secondary)
    case .unsupportedLocale:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.secondary)
    case .needsModel:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).textSelection(.enabled)
      Button("Install Speech Model…") { controller.installVoiceModel() }
        .buttonStyle(.borderedProminent).tint(.accentColor)
    case .downloading(let progress):
      ProgressView(value: progress) { Text(state.voiceMessage).font(.caption) }
      Button("Cancel Installation") { controller.cancelVoiceModelInstallation() }
        .buttonStyle(.bordered)
    case .waitingForModel:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).fixedSize(
        horizontal: false, vertical: true)
      Button("Check Again") { controller.refreshVoiceAvailability() }
        .buttonStyle(.bordered)
    case .ready:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).fixedSize(
        horizontal: false, vertical: true)
      Button("Start Follow Voice") { controller.startVoiceFollow() }
        .buttonStyle(.borderedProminent).tint(.accentColor)
    case .requestingMicrophone, .starting:
      ProgressView(state.voiceMessage).controlSize(.small)
    case .microphoneDenied:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).fixedSize(
        horizontal: false, vertical: true)
      HStack {
        Button("Open Microphone Settings…") { controller.openMicrophoneSettings() }
        Button("Try Again") { controller.startVoiceFollow() }
      }
    case .listening, .holding:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary)
      Button("Stop Follow Voice") { controller.stopVoiceFollow() }
        .buttonStyle(.bordered).tint(.red)
    case .commandPaused:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).fixedSize(
        horizontal: false, vertical: true)
      HStack {
        Button("Resume Following") { controller.startVoiceFollow(resume: true) }
        Button("Stop Following") { controller.stopVoiceFollow() }
      }
    case .suspended:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).fixedSize(
        horizontal: false, vertical: true)
      HStack {
        Button("Resume Following") { controller.startVoiceFollow(resume: true) }
        Button("Stop Following") { controller.stopVoiceFollow() }
      }
    case .failed:
      Text(state.voiceMessage).font(.caption).foregroundStyle(.primary).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Button("Check Again") { controller.refreshVoiceAvailability() }
        .buttonStyle(.bordered)
    }
  }
  private var voiceStatus: (title: String, symbol: String, color: Color)? {
    switch state.voiceState {
    case .hidden: nil
    case .checking: ("Checking", "ellipsis.circle.fill", Color(nsColor: .secondaryLabelColor))
    case .unavailable: ("Unavailable", "xmark.circle.fill", .red)
    case .unsupportedLocale: ("Language unavailable", "globe", .orange)
    case .needsModel: ("Model needed", "arrow.down.circle.fill", .orange)
    case .downloading: ("Installing", "arrow.down.circle.fill", .blue)
    case .waitingForModel: ("Waiting for model", "hourglass", .orange)
    case .ready: ("Ready", "checkmark.circle.fill", .green)
    case .requestingMicrophone: ("Microphone permission", "mic", .blue)
    case .microphoneDenied: ("Microphone off", "mic.slash.fill", .red)
    case .starting: ("Starting", "waveform", .blue)
    case .listening: ("Listening", "waveform", .red)
    case .holding: ("Holding", "pause.circle.fill", .orange)
    case .commandPaused: ("Paused · command ready", "pause.circle.fill", .orange)
    case .suspended: ("Paused", "pause.circle.fill", Color(nsColor: .secondaryLabelColor))
    case .failed: ("Needs attention", "exclamationmark.triangle.fill", .red)
    }
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
        .tracking(0.8).foregroundStyle(Color.primary.opacity(0.78))
      content
      Divider().padding(.top, 4)
    }
  }
}

@MainActor private struct CameraDockPlacementMapPreview: NSViewRepresentable {
  let map: CameraDockPlacementMap

  func makeNSView(context: Context) -> CameraDockPlacementMapView {
    let view = CameraDockPlacementMapView(frame: .zero)
    view.map = map
    return view
  }

  func updateNSView(_ view: CameraDockPlacementMapView, context: Context) {
    view.map = map
  }
}
