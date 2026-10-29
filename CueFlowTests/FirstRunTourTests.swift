import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

private final class FocusStandIn: NSView {
  override var acceptsFirstResponder: Bool { true }
}

/// Holds the completed-tour flag without a preferences suite. A suite flushes a
/// plist when the test process exits, after any in-process delete.
private final class MemoryDefaults: UserDefaults {
  private var values: [String: Any] = [:]

  override func set(_ value: Bool, forKey defaultName: String) {
    values[defaultName] = value
  }

  override func set(_ value: Any?, forKey defaultName: String) {
    if let value {
      values[defaultName] = value
    } else {
      values.removeValue(forKey: defaultName)
    }
  }

  override func bool(forKey defaultName: String) -> Bool {
    values[defaultName] as? Bool ?? false
  }

  override func object(forKey defaultName: String) -> Any? {
    values[defaultName]
  }

  override func removeObject(forKey defaultName: String) {
    values.removeValue(forKey: defaultName)
  }
}

@Suite(.serialized) @MainActor struct FirstRunTourTests {
  init() { _ = NSApplication.shared }

  private func turn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func open() async -> (OperatorWindowController, UserDefaults, NSWindow) {
    let defaults = MemoryDefaults(suiteName: nil)!
    let controller = OperatorWindowController(document: ScriptDocument())
    controller.tourDefaults = defaults
    let window = controller.window!
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    for _ in 0..<5 { await turn() }
    #expect(window.makeFirstResponder(controller.editor))
    return (controller, defaults, window)
  }

  private func close(
    _ controller: OperatorWindowController, defaults: inout UserDefaults?, suite: String
  ) {
    controller.preview.reflection.viewport.driver?.stop()
    controller.floating?.reflection.viewport.driver?.stop()
    controller.output?.reflection.viewport.driver?.stop()
    controller.close()
    defaults = nil
    deleteLegacySuitePlist(suite)
  }

  /// Earlier runs registered these suite names. Remove the plist if one remains.
  private func deleteLegacySuitePlist(_ suite: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Preferences/\(suite).plist")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    if unlink(url.path) != 0 {
      let code = errno
      if code != ENOENT {
        Issue.record(
          "Could not delete \(url.path) (errno \(code)). Remove that preferences file and rerun the tour tests."
        )
      }
    }
  }

  @Test func unsetFlagShowsStepOneAndReplayIgnoresCompletedFlag() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a1"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    #expect(controller.tour.currentStep == .script)
    #expect(NSApp.modalWindow == nil)
    controller.tour.end()
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
    let again = OperatorWindowController(document: ScriptDocument())
    again.tourDefaults = defaults!
    again.window?.makeKeyAndOrderFront(nil)
    again.startTourIfFirstRun()
    #expect(!again.tour.isActive)
    again.welcomeTourAction()
    #expect(again.tour.isActive)
    #expect(again.tour.currentStep == .script)
    again.tour.end()
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
    again.preview.reflection.viewport.driver?.stop()
    again.close()
  }

  @Test func endingsSetTheFlagAndReplaySkipFromUnsetSetsIt() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a2"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    controller.startTourIfFirstRun()
    controller.tour.end()
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    while controller.tour.currentStep != .present, controller.tour.isActive {
      controller.tour.next()
    }
    #expect(controller.tour.currentStep == .present)
    controller.tour.end()
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
    #expect(!controller.tour.isActive)

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.window?.makeKeyAndOrderFront(nil)
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    controller.toggle()
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
    #expect(controller.session.state != .idle)
    controller.stop()

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    controller.showFloating()
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
    controller.hideOutput()
    controller.stop()

    defaults!.set(true, forKey: FirstRunTour.completedKey)
    controller.welcomeTourAction()
    #expect(controller.tour.isActive)
    controller.tour.end()
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.welcomeTourAction()
    #expect(controller.tour.isActive)
    controller.tour.end()
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
  }

  @Test func editorKeepsFocusAndSelectionAcrossSteps() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a3"
    let (controller, openedDefaults, window) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    let editor = controller.editor
    editor.setSelectedRange(NSRange(location: 1, length: 0))
    let range = editor.selectedRange()
    controller.startTourIfFirstRun()
    func stillEditing() {
      #expect(window.firstResponder === editor)
      #expect(editor.selectedRange() == range)
      #expect(!OperatorWindow.acceptsTransport(editor))
      #expect(NSApp.modalWindow == nil)
    }
    stillEditing()
    #expect(controller.tour.currentStep == .script)
    controller.tour.next()
    stillEditing()
    #expect(controller.tour.currentStep == .pace)
    controller.tour.next()
    stillEditing()
    #expect(controller.tour.currentStep == .play)
    controller.tour.next()
    stillEditing()
    #expect(controller.tour.currentStep == .present)
    controller.tour.back()
    stillEditing()
    #expect(controller.tour.currentStep == .play)
  }

  @Test func tourDoesNotEditTheDocument() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a4"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    let script = controller.script
    let revision = script.revision
    let before = try script.data(ofType: ScriptDocument.nativeType)
    #expect(!script.isDocumentEdited)
    controller.startTourIfFirstRun()
    controller.tour.next()
    controller.tour.next()
    controller.tour.next()
    controller.tour.back()
    controller.tour.end()
    #expect(!script.isDocumentEdited)
    #expect(script.revision == revision)
    #expect(try script.data(ofType: ScriptDocument.nativeType) == before)
    #expect(controller.session.state == .idle)
  }

  @Test func blockedStatesDoNotStartAndDisableHelp() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a6"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    let previousMenu = NSApp.mainMenu
    let previousHelp = NSApp.helpMenu
    let delegate = AppDelegate()
    delegate.buildMenu()
    defer {
      NSApp.mainMenu = previousMenu
      NSApp.helpMenu = previousHelp
    }
    let help = try #require(NSApp.helpMenu)
    let item = try #require(help.items.first { $0.title == "Welcome Tour" })
    #expect(item.action == #selector(AppDelegate.welcomeTourAction))
    #expect(AppDelegate.welcomeTourEnabled(controller))

    controller.toggle()
    #expect(controller.session.state != .idle)
    #expect(!AppDelegate.welcomeTourEnabled(controller))
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(!defaults!.bool(forKey: FirstRunTour.completedKey))
    controller.welcomeTourAction()
    #expect(!controller.tour.isActive)
    controller.stop()
    #expect(AppDelegate.welcomeTourEnabled(controller))

    controller.showFloating()
    #expect(controller.floating != nil)
    #expect(!AppDelegate.welcomeTourEnabled(controller))
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(!defaults!.bool(forKey: FirstRunTour.completedKey))
    controller.hideOutput()
    controller.stop()
  }

  @Test func missingAnchorsAreSkippedAndNoneEndsTheTour() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a7"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    controller.editor.enclosingScrollView?.removeFromSuperview()
    controller.startTourIfFirstRun()
    #expect(controller.tour.currentStep == .pace)
    #expect(controller.tour.isActive)

    controller.transportChrome.removeFromSuperview()
    controller.playToolbarButton?.removeFromSuperview()
    controller.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "present" }?.view?
      .removeFromSuperview()
    controller.tour.next()
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))

    defaults!.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(defaults!.bool(forKey: FirstRunTour.completedKey))
  }

  @Test func stepCopyIsCueGlass() {
    #expect(TourStep.script.title == "Welcome to CueGlass")
    #expect(
      TourStep.script.body
        == "Type or paste your script here, or open a TXT or RTF file with File ▸ Open (⌘O). You can also drop a file onto this window."
    )
    #expect(TourStep.pace.title == "Set your pace")
    #expect(
      TourStep.pace.body
        == "Choose how fast the script moves, in lines per minute. Drag the slider or type a number. You can change it while it plays."
    )
    #expect(TourStep.play.title == "Play in the preview")
    #expect(
      TourStep.play.body
        == "Press Play to start. Space also plays and pauses once you click outside the script text. Editing is locked while a take is playing."
    )
    #expect(TourStep.present.title == "Show it to your audience")
    #expect(
      TourStep.present.body
        == "Present sends the prompt to a display, a floating window, or the Camera Dock under the notch. Press Esc to stop presenting. Replay this tour any time from Help ▸ Welcome Tour."
    )
    for step in TourStep.allCases {
      #expect(!step.title.contains("CueFlow"))
      #expect(!step.body.contains("CueFlow"))
    }
  }

  @Test func helpMenuOffersWelcomeTour() throws {
    let previousMenu = NSApp.mainMenu
    let previousHelp = NSApp.helpMenu
    let delegate = AppDelegate()
    delegate.buildMenu()
    defer {
      NSApp.mainMenu = previousMenu
      NSApp.helpMenu = previousHelp
    }
    let help = try #require(NSApp.helpMenu)
    let item = try #require(help.items.first { $0.title == "Welcome Tour" })
    #expect(item.action == #selector(AppDelegate.welcomeTourAction))
    #expect(item.target === delegate)
    #expect(!AppDelegate.welcomeTourEnabled(nil))
  }

  @Test func nextRestoresEditorOnlyWhenPopoverTookFocus() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a11"
    let (controller, openedDefaults, window) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    let editor = controller.editor
    controller.startTourIfFirstRun()
    #expect(window.firstResponder === editor)
    #expect(controller.tour.currentStep == .script)

    let stolen = FocusStandIn(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
    var claimed = false
    controller.tour.testingInstallStolenResponder = {
      guard let content = controller.tour.testingPopoverContentView else { return }
      content.addSubview(stolen)
      claimed = stolen.isDescendant(of: content) && window.makeFirstResponder(stolen)
    }
    controller.tour.next()
    #expect(claimed)
    #expect(window.firstResponder === editor)
    #expect(controller.tour.currentStep == .pace)
    controller.tour.testingInstallStolenResponder = nil

    let pace = NSTextField(string: "120")
    pace.frame = NSRect(x: 8, y: 8, width: 80, height: 22)
    window.contentView?.addSubview(pace)
    #expect(window.makeFirstResponder(pace))
    let kept = window.firstResponder
    controller.tour.next()
    #expect(window.firstResponder === kept)
    #expect(kept !== editor)
    #expect(controller.tour.currentStep == .play)
  }

  /// SwiftUI's accessibility nodes answer the NSAccessibility getters but declare no
  /// Swift-visible conformance, so read them by key.
  private func property(_ node: NSObject, _ key: String) -> Any? {
    node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
  }

  /// Walks the accessibility tree under a node and returns each button's label.
  private func buttonLabels(in node: NSObject, depth: Int = 0) -> [String] {
    guard depth < 12 else { return [] }
    var labels: [String] = []
    if property(node, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue {
      labels.append(property(node, "accessibilityLabel") as? String ?? "")
    }
    for child in property(node, "accessibilityChildren") as? [NSObject] ?? [] {
      labels += buttonLabels(in: child, depth: depth + 1)
    }
    return labels
  }

  @Test func popoverButtonsCarryTheirVisibleTextAsAccessibilityLabels() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a12"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    // SwiftUI builds its accessibility tree only once an assistive client is attached.
    let names = ["AXEnhancedUserInterface", "AXManualAccessibility"]
    let app = NSApp as NSObject
    let prior = names.map {
      app.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: $0)?
        .takeUnretainedValue() as? NSNumber ?? false as NSNumber
    }
    func setAssistiveClient(_ values: [NSNumber]) {
      for (name, value) in zip(names, values) {
        _ = app.perform(
          NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: value, with: name)
      }
    }
    setAssistiveClient([true, true])
    defer { setAssistiveClient(prior) }
    controller.startTourIfFirstRun()
    for _ in 0..<5 { await turn() }
    var seen: [TourStep: [String]] = [:]
    while controller.tour.isActive, let step = controller.tour.currentStep {
      let content = try #require(controller.tour.testingPopoverContentView)
      seen[step] = buttonLabels(in: content).sorted()
      controller.tour.next()
    }
    #expect(seen[.script] == ["Next", "Skip Tour"])
    #expect(seen[.pace] == ["Back", "Next", "Skip Tour"])
    #expect(seen[.play] == ["Back", "Next", "Skip Tour"])
    #expect(seen[.present] == ["Back", "Done", "Skip Tour"])
  }

  private func anchorScreenRect(_ controller: OperatorWindowController, step: TourStep) throws
    -> NSRect
  {
    let anchor = try #require(step.anchor(in: controller))
    return try #require(anchor.window).convertToScreen(anchor.convert(anchor.bounds, to: nil))
  }

  /// Where the operator window sits on the screen. `flush` leaves no room above the
  /// toolbar, so AppKit has to shift or flip the popover, as it may on a small display.
  enum Placement: CaseIterable { case roomy, flush }

  private func place(_ window: NSWindow, _ placement: Placement) {
    guard let visible = window.screen?.visibleFrame else { return }
    let width = min(1100, visible.width - 40)
    let height = min(700, visible.height - 40)
    let top = placement == .flush ? visible.maxY : visible.maxY - 300
    window.setFrame(
      NSRect(
        x: visible.minX + 20, y: max(visible.minY, top - height), width: width, height: height),
      display: true)
    window.contentView?.layoutSubtreeIfNeeded()
  }

  /// A fresh show is the placement AppKit picks for this screen, whatever its size. The
  /// popover on screen must match it. The bug left it 117 to 125 pt off.
  private func expectPopoverMatchesFreshPlacement(_ controller: OperatorWindowController)
    async throws
  {
    for _ in 0..<8 { await turn() }
    let shown = try #require(controller.tour.testingPopoverContentView?.window).frame
    let fresh = try #require(controller.tour.testingFreshPopoverFrame)
    #expect(abs(shown.minX - fresh.minX) <= 1 && abs(shown.minY - fresh.minY) <= 1)
  }

  @Test(arguments: Placement.allCases)
  func popoverFollowsItsAnchorWhenTheInspectorToggles(placement: Placement) async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a13.\(placement)"
    let (controller, openedDefaults, window) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    place(window, placement)
    controller.startTourIfFirstRun()
    while controller.tour.currentStep != .present, controller.tour.isActive {
      controller.tour.next()
    }
    #expect(controller.tour.currentStep == .present)
    try await expectPopoverMatchesFreshPlacement(controller)
    var previous = try anchorScreenRect(controller, step: .present)
    for _ in 0..<2 {
      controller.toggleInspector()
      for _ in 0..<8 { await turn() }
      window.contentView?.layoutSubtreeIfNeeded()
      let moved = try anchorScreenRect(controller, step: .present)
      #expect(moved != previous, "the toggle must reflow the toolbar or the test proves nothing")
      previous = moved
      #expect(controller.tour.isActive)
      try await expectPopoverMatchesFreshPlacement(controller)
    }
  }

  @Test func completedFlagSurvivesANewTourInstance() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a10"
    let (controller, openedDefaults, _) = await open()
    var defaults: UserDefaults? = openedDefaults
    defer { close(controller, defaults: &defaults, suite: suite) }
    controller.startTourIfFirstRun()
    controller.tour.end()
    let relaunch = FirstRunTour(controller: controller, defaults: openedDefaults)
    #expect(relaunch.isCompleted)
    #expect(!relaunch.isActive)
  }
}
