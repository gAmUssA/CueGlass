import AppKit
import SwiftUI

/// One coachmark in the first-run tour. Copy is the product text; tests assert it as literals.
enum TourStep: CaseIterable {
  case script, pace, play, present

  var title: String {
    switch self {
    case .script: "Welcome to CueGlass"
    case .pace: "Set your pace"
    case .play: "Play in the preview"
    case .present: "Show it to your audience"
    }
  }

  var body: String {
    switch self {
    case .script:
      "Type or paste your script here, or open a TXT or RTF file with File ▸ Open (⌘O). You can also drop a file onto this window."
    case .pace:
      "Choose how fast the script moves, in lines per minute. Drag the slider or type a number. You can change it while it plays."
    case .play:
      "Press Play to start. Space also plays and pauses once you click outside the script text. Editing is locked while a take is playing."
    case .present:
      "Present sends the prompt to a display, a floating window, or the Camera Dock under the notch. Press Esc to stop presenting. Replay this tour any time from Help ▸ Welcome Tour."
    }
  }

  var edge: NSRectEdge {
    switch self {
    case .script: .maxX
    case .pace: .maxY
    case .play, .present: .minY
    }
  }

  /// Nil when the control is not in a window, so the tour skips that step.
  @MainActor func anchor(in controller: OperatorWindowController) -> NSView? {
    let view: NSView? =
      switch self {
      case .script: controller.editor.enclosingScrollView
      case .pace: controller.transportChrome
      case .play: controller.playToolbarButton
      case .present:
        controller.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "present" }?.view
      }
    guard let view, view.window != nil, !view.isHidden else { return nil }
    return view
  }
}

struct TourStepView: View {
  let step: TourStep
  let index: Int
  let count: Int
  let onSkip: () -> Void
  let onBack: () -> Void
  let onNext: () -> Void
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(step.title).font(.headline)
      Text(step.body).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
      Text("\(index + 1) of \(count)").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Skip Tour", action: onSkip).buttonStyle(.borderless).focusable(false)
        Spacer()
        if index > 0 { Button("Back", action: onBack).focusable(false) }
        if index + 1 < count {
          Button("Next", action: onNext).focusable(false)
        } else {
          Button("Done", action: onDone).focusable(false)
        }
      }
    }
    .padding(16)
    .frame(width: 300, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("CueGlass tour, step \(index + 1) of \(count)")
  }
}

/// The popover explains the editor. Its content does not take keyboard focus from the script.
@MainActor final class TourHostingView: NSHostingView<TourStepView> {
  override var acceptsFirstResponder: Bool { false }
}

@MainActor final class TourContentController: NSHostingController<TourStepView> {
  var onCancel: (() -> Void)?
  override func loadView() {
    view = TourHostingView(rootView: rootView)
  }
  @objc override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Non-modal coachmarks. Nothing here is written into a document.
@MainActor final class FirstRunTour: NSObject, NSPopoverDelegate {
  static let completedKey = "firstRunTourCompleted"
  private weak var controller: OperatorWindowController?
  private let defaults: UserDefaults
  private let popover = NSPopover()
  private var index = 0
  private var advancing = false
  private var savedResponder: NSResponder?
  private(set) var isActive = false
  private(set) var currentStep: TourStep?
  /// The headless runner never lets the popover take the responder. A test
  /// installs that state after the popover is shown and before the restore.
  var testingInstallStolenResponder: (() -> Void)?
  var testingPopoverContentView: NSView? { popover.contentViewController?.view }

  init(controller: OperatorWindowController, defaults: UserDefaults = .standard) {
    self.controller = controller
    self.defaults = defaults
    super.init()
    popover.behavior = .applicationDefined
    popover.animates = false
    popover.delegate = self
  }

  var isCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

  /// Auto-start. A completed flag or a live take leaves the flag unchanged.
  func start(force: Bool) {
    guard let controller else { return }
    if !force, isCompleted { return }
    guard controller.canPresentTour else { return }
    dismissPopover()
    savedResponder = controller.window?.firstResponder
    index = 0
    isActive = true
    showCurrent()
  }

  func next() {
    guard isActive else { return }
    index += 1
    showCurrent()
  }

  func back() {
    guard isActive, let controller else { return }
    let steps = Array(TourStep.allCases)
    var previous = index - 1
    while previous >= 0 {
      if let anchor = steps[previous].anchor(in: controller) {
        index = previous
        show(steps[previous], from: anchor)
        return
      }
      previous -= 1
    }
  }

  /// Ends the tour and records completion. Replay does not clear a flag that is already set.
  func end() {
    guard isActive else { return }
    let popoverWasKey = popover.contentViewController?.view.window?.isKeyWindow == true
    let responder = savedResponder
    let window = controller?.window
    persistCompletion()
    isActive = false
    currentStep = nil
    dismissPopover()
    if popoverWasKey { window?.makeKey() }
    guard window?.firstResponder == nil, let responder else { return }
    let stillAttached = (responder as? NSView)?.window === window || responder === window
    if stillAttached { window?.makeFirstResponder(responder) }
  }

  /// A take or presentation surface replaces the tour and counts as finishing it.
  func stopIfBlocked() {
    guard isActive, let controller else { return }
    if controller.session.state != .idle || controller.output != nil || controller.floating != nil {
      end()
    }
  }

  func popoverDidClose(_ notification: Notification) {
    guard isActive, !advancing else { return }
    end()
  }

  private func showCurrent() {
    guard isActive, let controller else { return }
    let steps = Array(TourStep.allCases)
    while index < steps.count {
      if let anchor = steps[index].anchor(in: controller) {
        show(steps[index], from: anchor)
        return
      }
      index += 1
    }
    end()
  }

  private func show(_ step: TourStep, from anchor: NSView) {
    let steps = TourStep.allCases
    let position = steps.firstIndex(of: step) ?? 0
    let host = TourContentController(
      rootView: TourStepView(
        step: step, index: position, count: steps.count,
        onSkip: { [weak self] in self?.end() },
        onBack: { [weak self] in self?.back() },
        onNext: { [weak self] in self?.next() },
        onDone: { [weak self] in self?.end() }))
    host.onCancel = { [weak self] in self?.end() }
    currentStep = step
    advancing = true
    if popover.isShown { popover.close() }
    popover.contentViewController = host
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: step.edge)
    advancing = false
    testingInstallStolenResponder?()
    // Restore the editor only when the popover took the responder. A control
    // the operator moved to, such as the pace field, keeps focus.
    keepSavedResponder()
  }

  private func keepSavedResponder() {
    guard let window = controller?.window, let responder = savedResponder else { return }
    guard window.firstResponder !== responder else { return }
    guard responderWasTakenByPopover(window) else { return }
    let stillAttached = (responder as? NSView)?.window === window || responder === window
    guard stillAttached else { return }
    window.makeFirstResponder(responder)
  }

  /// Nil means the popover window took key focus. A descendant of the coachmark
  /// is the button the popover installed. Any other responder was chosen by the operator.
  private func responderWasTakenByPopover(_ window: NSWindow) -> Bool {
    let current = window.firstResponder
    if current == nil { return true }
    guard let root = popover.contentViewController?.view, let view = current as? NSView else {
      return false
    }
    return view === root || view.isDescendant(of: root)
  }

  private func dismissPopover() {
    advancing = true
    if popover.isShown { popover.close() }
    advancing = false
  }

  private func persistCompletion() {
    if defaults === UserDefaults.standard,
      ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] == "1"
    {
      return
    }
    if defaults.bool(forKey: Self.completedKey) { return }
    defaults.set(true, forKey: Self.completedKey)
  }
}
