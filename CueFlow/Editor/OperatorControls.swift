import AppKit
import CueFlowCore
import SwiftUI

struct OperatorControls: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  @State private var selectedCommand = PlaybackCommand.toggle
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
  @AppStorage("inspectorTab") private var inspectorTab = InspectorTab.text.rawValue
  private enum InspectorTab: String, CaseIterable {
    case text, playback, output
    var title: String {
      switch self {
      case .text: "Text"
      case .playback: "Playback"
      case .output: "Output"
      }
    }
  }
  private var tab: InspectorTab { InspectorTab(rawValue: inspectorTab) ?? .text }
  private var preservesSource: Bool { state.style.mode == .preserveSource }
  private var englishVoice: Bool {
    Locale(identifier: state.voiceLocale).language.languageCode?.identifier == "en"
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Inspector", selection: $inspectorTab) {
        ForEach(InspectorTab.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
      }
      .pickerStyle(.segmented).labelsHidden()
      .padding(.horizontal, 14).padding(.vertical, 8)
      .accessibilityLabel("Inspector section")
      Divider()
      Form {
        switch tab {
        case .text: textTab
        case .playback: playbackTab
        case .output: outputTab
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
    }
    .environment(\.colorScheme, state.darkAppearance ? .dark : .light)
    .font(.system(size: 13)).controlSize(.small)
    .onChange(of: state.countdown) { controller.saveOperatorPreferences() }
    .onChange(of: state.hideControls) { controller.saveOperatorPreferences() }
  }

  // MARK: Text

  @ViewBuilder private var textTab: some View {
    Section("Font") {
      Picker(
        "Family",
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
      }
      .disabled(preservesSource)
      Picker("Weight", selection: binding(\.fontWeight)) {
        ForEach(ReadingStyle.Weight.allCases, id: \.self) {
          Text($0.rawValue.capitalized).tag($0)
        }
      }
      .disabled(preservesSource)
      LabeledContent("Size") {
        HStack(spacing: 4) {
          TextField("Size", value: binding(\.fontSize), format: .number).labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 54).multilineTextAlignment(.trailing)
          Text("pt").foregroundStyle(.secondary)
        }
      }
      valueSlider("Line height", path: \.lineHeightMultiplier, range: 1...2)
      LabeledContent("Typography") {
        Picker("Typography", selection: binding(\.mode)) {
          Text("Normalized").tag(ReadingStyle.Mode.normalized)
          Text("Preserve Source").tag(ReadingStyle.Mode.preserveSource)
        }
        .labelsHidden()
        .help(
          "Normalized applies the font above to the whole script. Preserve Source keeps the script's own fonts and emphasis; Size scales them."
        )
      }
      HStack {
        Spacer()
        Button("Other Fonts…") { controller.otherFonts() }.disabled(preservesSource)
      }
    }
    Section("Layout") {
      valueSlider("Column width", path: \.columnWidthFraction, range: 0.25...1)
      valueSlider("Side margins", path: \.sideMarginFraction, range: 0...0.25)
      valueSlider("Paragraph spacing", path: \.paragraphSpacing, range: 0...200)
    }
    Section {
      ColorPicker("Text", selection: color(\.foregroundRGBA))
      ColorPicker("Background", selection: color(\.backgroundRGBA))
      valueSlider("Panel opacity", path: \.textPanelOpacity, range: 0...1)
    } header: {
      Text("Colors")
    } footer: {
      if !state.contrastWarning.isEmpty {
        Label(state.contrastWarning, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    Section("Reading Guide") {
      Picker(
        "Guide",
        selection: Binding(
          get: {
            state.style.showsReadingGuide ? state.style.readingGuideStyle.rawValue : "off"
          },
          set: { value in
            var style = state.style
            if value == "off" {
              style.showsReadingGuide = false
            } else if let next = ReadingStyle.GuideStyle(rawValue: value) {
              style.showsReadingGuide = true
              style.readingGuideStyle = next
            }
            controller.changeStyle(style)
          })
      ) {
        Text("Line").tag(ReadingStyle.GuideStyle.line.rawValue)
        Text("Triangle").tag(ReadingStyle.GuideStyle.triangle.rawValue)
        Text("Both").tag(ReadingStyle.GuideStyle.triangleAndLine.rawValue)
        Text("Off").tag("off")
      }
      .pickerStyle(.segmented)
      valueSlider("Position", path: \.readingGuideFraction, range: 0...1)
      valueSlider("Guide opacity", path: \.readingGuideOpacity, range: 0...1)
      valueSlider("Edge fade", path: \.edgeFadeFraction, range: 0...0.3)
    }
  }

  // MARK: Playback

  @ViewBuilder private var playbackTab: some View {
    Section("Pace") {
      LabeledContent("Maximum") {
        HStack(spacing: 8) {
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
          Text("\(Int(state.maximum)) lpm").foregroundStyle(.secondary).monospacedDigit()
            .frame(width: 52, alignment: .trailing)
        }
      }
      .help("Upper bound for the pace slider, arrow keys, and Follow Voice.")
      Stepper("Fine step: \(Int(state.fineStep)) lpm", value: $state.fineStep, in: 1...10)
        .onChange(of: state.fineStep) { controller.saveOperatorPreferences() }
        .help("Pace change for ↑ and ↓.")
      Stepper("Jump step: \(Int(state.jumpStep)) lpm", value: $state.jumpStep, in: 1...60)
        .onChange(of: state.jumpStep) { controller.saveOperatorPreferences() }
        .help("Pace change for ⇧↑ and ⇧↓.")
      Picker("Countdown", selection: $state.countdown) {
        Text("Off").tag(0)
        ForEach([3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
      }
    }
    Section {
      LabeledContent("Finish in") {
        HStack(spacing: 4) {
          TextField("Seconds", value: $state.duration, format: .number).labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 64).multilineTextAlignment(.trailing)
          Text("s").foregroundStyle(.secondary)
        }
      }
      HStack {
        Spacer()
        Button("Enable Timed Scrolling") {
          controller.enableTimedScrolling(seconds: state.duration)
        }
      }
    } header: {
      Text("Timed Scrolling")
    } footer: {
      Text(
        "Fixes the pace so the take ends on time. Manual pace changes and Follow Voice turn it off."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    if state.voiceAvailable {
      Section {
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
        .help(
          "English is validated. Other languages depend on the models macOS offers. Selecting one does not open the microphone."
        )
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
          "Changing the microphone while following moves capture to it without stopping the take."
        )
        .accessibilityLabel("Follow Voice microphone")
        if !state.voiceInputNotice.isEmpty {
          Label(state.voiceInputNotice, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .accessibilityLabel("Microphone notice: \(state.voiceInputNotice)")
        }
        followVoiceControls
      } header: {
        Text("Follow Voice")
      } footer: {
        Text(
          englishVoice
            ? "Say “CueGlass” or “Prompter”, then “pause”, “resume”, “stop” or “stop take”."
            : "Spoken commands require English."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    Section {
      Toggle("Hide controls while playing", isOn: $state.hideControls)
      Picker("Command", selection: $selectedCommand) {
        ForEach(PlaybackCommand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      LabeledContent("Shortcut") {
        Text(
          CommandRouter.map.bindings.filter { $0.command == selectedCommand }.map {
            $0.chord.label
          }
          .joined(separator: " · ")
        )
        .foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Reset Defaults") {
          CommandRouter.map = CommandMap()
          controller.perform {
            try CommandRouter.save()
            controller.refresh()
            state.status = "Default shortcuts restored"
          }
        }
        Button("Record Shortcut…") { controller.recordShortcut(selectedCommand) }
      }
    } header: {
      Text("Controls")
    } footer: {
      Text(
        "Shortcuts work while CueGlass is frontmost or a clicker targets it. Nothing is monitored globally."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  // MARK: Output

  @ViewBuilder private var outputTab: some View {
    Section {
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
      Picker(
        "Display",
        selection: Binding(
          get: { state.selectedDisplay }, set: { controller.selectDisplay($0) })
      ) {
        if !state.displays.contains(state.selectedDisplay) {
          // A selection that is not attached still needs a visible title.
          Text(
            state.displays.isEmpty
              ? "No display connected"
              : state.selectedDisplay == "disconnected" ? "Disconnected" : "Choose a display"
          )
          .tag(state.selectedDisplay)
        }
        ForEach(state.displays, id: \.self) { key in Text(controller.displayName(key)).tag(key) }
      }
      .disabled(state.displays.isEmpty)
      if controller.cameraDock == nil {
        Toggle("Reflect horizontally", isOn: $state.horizontal).onChange(of: state.horizontal) {
          controller.reflect()
        }
        Toggle("Reflect vertically", isOn: $state.vertical).onChange(of: state.vertical) {
          controller.reflect()
        }
        Toggle("Preview as output", isOn: $state.calibrated).onChange(of: state.calibrated) {
          controller.reflect()
        }
        HStack {
          Spacer()
          Button("Calibration Pattern…") { controller.calibration() }
        }
      }
    } header: {
      Text("Presentation")
    } footer: {
      if controller.selectedPresentationSurface == "cameraDock" {
        Text(OperatorWindowController.cameraDockCaptureDisclosure)
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    Section {
      if controller.selectedPresentationSurface == "cameraDock",
        state.cameraDockFirstUseCalloutVisible
      {
        VStack(alignment: .leading, spacing: 8) {
          Text("Camera Dock is ready").font(.subheadline.weight(.semibold))
          Text(OperatorWindowController.cameraDockExplainer)
            .font(.caption).fixedSize(horizontal: false, vertical: true)
          Button("Got it") { controller.acknowledgeCameraDockExplainer() }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera Dock first-use information")
      }
      if let map = controller.cameraDockPlacementMap {
        CameraDockPlacementMapPreview(map: map)
          .aspectRatio(map.displayAspectRatio, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel(Text(map.caption))
          .help(map.caption)
      } else {
        Text("Choose a display to preview Camera Dock placement.")
          .font(.caption).foregroundStyle(.secondary)
      }
      LabeledContent("Width") {
        HStack(spacing: 8) {
          Slider(
            value: Binding(
              get: { state.cameraDockWidth },
              set: { controller.setCameraDockWidth($0) }),
            in: 360...760, step: 20
          )
          .accessibilityLabel("Camera Dock width")
          Text("\(Int(state.cameraDockWidth.rounded())) pt").foregroundStyle(.secondary)
            .monospacedDigit().frame(width: 52, alignment: .trailing)
        }
      }
      Stepper(
        "Visible lines: \(state.cameraDockLineCount)",
        value: Binding(
          get: { state.cameraDockLineCount },
          set: { controller.setCameraDockLineCount($0) }),
        in: 2...5)
      LabeledContent("Nudge") {
        HStack(spacing: 8) {
          Slider(
            value: Binding(
              get: { state.cameraDockHorizontalNudge },
              set: { controller.setCameraDockHorizontalNudge($0) }),
            in: -120...120, step: 8
          )
          .accessibilityLabel("Camera Dock horizontal nudge")
          Text("\(Int(state.cameraDockHorizontalNudge.rounded())) pt").foregroundStyle(.secondary)
            .monospacedDigit().frame(width: 52, alignment: .trailing)
        }
      }
      Toggle(
        "Notch island on displays without a notch",
        isOn: Binding(
          get: { state.cameraDockNotchIsland },
          set: { controller.setCameraDockNotchIsland($0) })
      )
      .accessibilityLabel("Notch island on displays without a notch")
      HStack {
        Spacer()
        Button("Reset Placement") { controller.resetCameraDockPreferences() }
      }
    } header: {
      Text("Camera Dock")
    }
    .onAppear { controller.setCameraDockPlacementPreviewExpanded(true) }
    .onDisappear { controller.setCameraDockPlacementPreviewExpanded(false) }
    Section {
      LabeledContent("Opacity") {
        HStack(spacing: 8) {
          Slider(value: $state.floatingOpacity, in: 0.3...1).onChange(of: state.floatingOpacity) {
            controller.updateFloatingOptions()
            controller.saveOperatorPreferences()
          }.accessibilityLabel("Whole floating window opacity")
          Text("\(Int(state.floatingOpacity * 100))%").foregroundStyle(.secondary)
            .monospacedDigit().frame(width: 52, alignment: .trailing)
        }
      }
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
    } header: {
      Text("Floating Window")
    } footer: {
      if !state.contrastWarning.isEmpty {
        Label(state.contrastWarning, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
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
    LabeledContent(label) {
      HStack(spacing: 8) {
        Slider(value: binding(path), in: range).accessibilityLabel(label)
        Text(sliderValue(path)).foregroundStyle(.secondary).monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
    }
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
