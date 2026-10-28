import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@Suite(.serialized) @MainActor struct FirstRunTourTests {
  init() { _ = NSApplication.shared }

  private func turn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func open(
    _ suite: String
  ) async -> (OperatorWindowController, UserDefaults, NSWindow) {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
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

  private func close(_ controller: OperatorWindowController, suite: String) {
    controller.preview.reflection.viewport.driver?.stop()
    controller.floating?.reflection.viewport.driver?.stop()
    controller.output?.reflection.viewport.driver?.stop()
    controller.close()
    UserDefaults().removePersistentDomain(forName: suite)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  @Test func unsetFlagShowsStepOneAndReplayIgnoresCompletedFlag() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a1"
    let (controller, defaults, _) = await open(suite)
    defer { close(controller, suite: suite) }
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    #expect(controller.tour.currentStep == .script)
    #expect(NSApp.modalWindow == nil)
    controller.tour.end()
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
    let again = OperatorWindowController(document: ScriptDocument())
    again.tourDefaults = defaults
    again.window?.makeKeyAndOrderFront(nil)
    again.startTourIfFirstRun()
    #expect(!again.tour.isActive)
    again.welcomeTourAction()
    #expect(again.tour.isActive)
    #expect(again.tour.currentStep == .script)
    again.tour.end()
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
    again.preview.reflection.viewport.driver?.stop()
    again.close()
  }

  @Test func endingsSetTheFlagAndReplaySkipFromUnsetSetsIt() async throws {
    let suite = "com.example.cueflow.tests.first-run-tour.a2"
    let (controller, defaults, _) = await open(suite)
    defer { close(controller, suite: suite) }
    controller.startTourIfFirstRun()
    controller.tour.end()
    #expect(!controller.tour.isActive)
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    while controller.tour.currentStep != .present, controller.tour.isActive {
      controller.tour.next()
    }
    #expect(controller.tour.currentStep == .present)
    controller.tour.end()
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
    #expect(!controller.tour.isActive)

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    #expect(!controller.tour.isActive)
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.window?.makeKeyAndOrderFront(nil)
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    controller.toggle()
    #expect(!controller.tour.isActive)
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
    #expect(controller.session.state != .idle)
    controller.stop()

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    #expect(controller.tour.isActive)
    controller.showFloating()
    #expect(!controller.tour.isActive)
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
    controller.hideOutput()
    controller.stop()

    defaults.set(true, forKey: FirstRunTour.completedKey)
    controller.welcomeTourAction()
    #expect(controller.tour.isActive)
    controller.tour.end()
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.welcomeTourAction()
    #expect(controller.tour.isActive)
    controller.tour.end()
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
  }

  @Test func editorKeepsFocusAndSelectionAcrossSteps() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a3"
    let (controller, _, window) = await open(suite)
    defer { close(controller, suite: suite) }
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
    let (controller, _, _) = await open(suite)
    defer { close(controller, suite: suite) }
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
    let (controller, defaults, _) = await open(suite)
    defer { close(controller, suite: suite) }
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
    // This process cannot become the active app, so the key-window lookup stays nil.
    // The menu rule is still asserted with the controller it would receive.
    #expect(!NSApp.isActive)
    #expect(delegate.current == nil)
    #expect(!delegate.validateMenuItem(item))
    #expect(AppDelegate.welcomeTourEnabled(controller))

    controller.toggle()
    #expect(controller.session.state != .idle)
    #expect(!AppDelegate.welcomeTourEnabled(controller))
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(!defaults.bool(forKey: FirstRunTour.completedKey))
    #expect(!delegate.validateMenuItem(item))
    controller.welcomeTourAction()
    #expect(!controller.tour.isActive)
    controller.stop()
    #expect(AppDelegate.welcomeTourEnabled(controller))

    controller.showFloating()
    #expect(controller.floating != nil)
    #expect(!AppDelegate.welcomeTourEnabled(controller))
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(!defaults.bool(forKey: FirstRunTour.completedKey))
    #expect(!delegate.validateMenuItem(item))
    controller.hideOutput()
    controller.stop()
  }

  @Test func missingAnchorsAreSkippedAndNoneEndsTheTour() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a7"
    let (controller, defaults, _) = await open(suite)
    defer { close(controller, suite: suite) }
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
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))

    defaults.set(false, forKey: FirstRunTour.completedKey)
    controller.startTourIfFirstRun()
    #expect(!controller.tour.isActive)
    #expect(defaults.bool(forKey: FirstRunTour.completedKey))
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
    #expect(!delegate.validateMenuItem(item))
  }

  @Test func completedFlagSurvivesANewTourInstance() async {
    let suite = "com.example.cueflow.tests.first-run-tour.a10"
    let (controller, defaults, _) = await open(suite)
    defer { close(controller, suite: suite) }
    controller.startTourIfFirstRun()
    controller.tour.end()
    let relaunch = FirstRunTour(controller: controller, defaults: defaults)
    #expect(relaunch.isCompleted)
    #expect(!relaunch.isActive)
  }
}
