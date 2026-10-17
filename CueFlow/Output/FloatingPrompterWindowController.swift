import AppKit
import CueFlowCore
import SwiftUI

@MainActor final class PresentationPanel: NSPanel {
  weak var operatorController: OperatorWindowController?
  override var canBecomeKey: Bool { true }
  override func keyDown(with event: NSEvent) {
    if !CommandRouter.route(event, window: self, controller: operatorController) {
      super.keyDown(with: event)
    }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      CommandRouter.route(event, window: self, controller: operatorController)
    {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
enum PrompterPlacement: Equatable {
  case floating
  case cameraDock
}

@MainActor final class FloatingPrompterWindowController: NSWindowController, NSWindowDelegate {
  let reflection = ReflectionContainerView(frame: .zero)
  let placement: PrompterPlacement
  var onClose: (() -> Void)?
  var root: FloatingRoot?
  var displayID: CGDirectDisplayID?
  private(set) var displayUUID: String?
  private(set) var dockPreferences: CameraDockPreferences
  private(set) var dockLocation: CameraDockLocation = .topOfDisplay
  private(set) var dockStyle: CameraDockVisualStyle = .detached
  private(set) var dockTopInset: CGFloat = 0
  private(set) var dockContentOffsetX: CGFloat = 0
  private(set) var dockLayout: CameraDockLayout?
  weak var operatorController: OperatorWindowController?

  var isCameraDock: Bool { placement == .cameraDock }
  var viewportSize: CGSize { root?.logicalSize ?? window?.contentView?.bounds.size ?? .zero }

  init(screen: NSScreen, controller: OperatorWindowController) {
    placement = .floating
    operatorController = controller
    let display = DisplayDescriptor.all().first { $0.screen == screen }
    displayID = display?.id
    displayUUID = display?.preference.uuid ?? screen.localizedName
    dockPreferences = .defaults(screenWidth: screen.frame.width)
    let visible = screen.visibleFrame
    var frame = CGRect(
      x: visible.midX - visible.width * 0.2, y: visible.maxY - visible.height * 0.3,
      width: visible.width * 0.4, height: visible.height * 0.3)
    let key =
      "floatingFrame-"
      + (DisplayDescriptor.all().first { $0.screen == screen }?.preference.uuid
        ?? screen.localizedName)
    if let stored = UserDefaults.standard.string(forKey: key) {
      let relative = NSRectFromString(stored)
      frame = relative.offsetBy(dx: visible.minX, dy: visible.minY)
    }
    frame = FrameClamp.clamp(frame, to: visible)
    let window = PresentationPanel(
      contentRect: frame,
      styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    super.init(window: window)
    configure(window: window, controller: controller, screen: screen, viewportSize: frame.size)
  }

  init?(
    cameraDockOn display: DisplayDescriptor, controller: OperatorWindowController,
    preferences: CameraDockPreferences
  ) {
    placement = .cameraDock
    operatorController = controller
    dockPreferences = preferences.normalized()
    let screen = display.screen
    displayID = display.id
    displayUUID = display.preference.uuid ?? screen.localizedName
    guard
      let geometry = Self.cameraDockLayout(
        display: display, preferences: dockPreferences, style: controller.state.style)
    else { return nil }
    dockLocation = geometry.placement.location
    dockStyle = geometry.style
    dockTopInset = CGFloat(geometry.contentTopInset)
    dockContentOffsetX = CGFloat(
      geometry.placement.contentFrame.minX - geometry.placement.frame.minX)
    dockLayout = geometry
    let frame = Self.cgRect(geometry.placement.frame)
    let window = PresentationPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false, screen: screen)
    super.init(window: window)
    configure(
      window: window, controller: controller, screen: screen,
      viewportSize: CGSize(width: geometry.viewportWidth, height: geometry.viewportHeight),
      cameraDockTopInset: dockTopInset, cameraDockContentOffsetX: dockContentOffsetX,
      cameraDockLayout: dockLayout)
    window.setFrame(frame, display: false)
  }

  private func configure(
    window: PresentationPanel, controller: OperatorWindowController, screen: NSScreen,
    viewportSize: CGSize, cameraDockTopInset: CGFloat = 0,
    cameraDockContentOffsetX: CGFloat = 0, cameraDockLayout: CameraDockLayout? = nil
  ) {
    window.operatorController = controller
    window.title = isCameraDock ? "CueGlass · Camera Dock" : "CueGlass · Floating Prompter"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovable = !isCameraDock
    window.isMovableByWindowBackground = !isCameraDock
    window.hidesOnDeactivate = false
    window.level = Self.cameraDockWindowLevel(isCameraDock: isCameraDock, style: dockStyle)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.hasShadow = !isCameraDock || dockStyle == .detached
    window.backgroundColor = .clear
    window.minSize =
      isCameraDock ? CGSize(width: 360, height: 120) : CGSize(width: 320, height: 180)
    if isCameraDock {
      window.collectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications,
      ]
      window.autorecalculatesKeyViewLoop = false
    }
    let root = FloatingRoot(
      reflection: reflection, controller: controller, placement: placement,
      cameraDockStyle: dockStyle, cameraDockTopInset: cameraDockTopInset,
      cameraDockContentOffsetX: cameraDockContentOffsetX, cameraDockLayout: cameraDockLayout)
    root.logicalSize = viewportSize
    self.root = root
    window.contentView = root
    window.delegate = self
    window.acceptsMouseMovedEvents = true
    reflection.wantsLayer = true
    reflection.layer?.cornerRadius = isCameraDock ? 0 : 14
    reflection.layer?.masksToBounds = true
    reflection.viewport.compactCountdown = isCameraDock
    if isCameraDock {
      reflection.viewport.centersText = true
      reflection.viewport.columnWidthFractionOverride = CameraDockGeometry.textColumnFraction
      reflection.viewport.hidesReadingGuide = true
      applyCameraDockTextPanelVisibility(style: controller.state.style)
      root.setAccessibilityElement(true)
      root.setAccessibilityLabel("CueGlass prompt")
      if let controls = root.cameraDockControls {
        root.setAccessibilityChildren(controls.accessibilityControls)
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("Use an explicit presentation initializer") }

  /// The Dock's black surface is the text panel. The viewport's own panel rectangle would
  /// otherwise show as a lighter column inside it, so hide it whenever the reading style's
  /// background is dark enough to disappear into the surface; keep a light panel visible
  /// so light-background styles stay legible.
  static func hidesTextPanel(for style: ReadingStyle) -> Bool {
    guard style.backgroundRGBA.count >= 3 else { return false }
    let luminance =
      0.2126 * style.backgroundRGBA[0] + 0.7152 * style.backgroundRGBA[1]
      + 0.0722 * style.backgroundRGBA[2]
    return luminance.isFinite && luminance < 0.18
  }

  private func applyCameraDockTextPanelVisibility(style: ReadingStyle) {
    guard isCameraDock else { return }
    reflection.viewport.panelBackground.isHidden = Self.hidesTextPanel(for: style)
  }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    root?.revealCameraDock()
  }

  /// Parks the attached Dock as a chin under the housing. The operator takes manual control
  /// first — playback pauses, a pending or spoken-paused Follow Voice start is cancelled and
  /// its microphone closed — so nothing can reopen the Dock until an explicit Play.
  func collapseToNotch() {
    guard isCameraDock, dockStyle == .attached, let controller = operatorController else {
      return
    }
    controller.takeManualControl("Collapse to Notch")
    root?.setCameraDockParked(true)
  }

  static func cameraDockLayout(
    display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> CameraDockLayout? {
    CameraDockGeometry.layout(
      on: display.cameraDockParameters, isBuiltIn: display.isBuiltIn,
      isMirrored: display.isMirrored, preferences: preferences,
      lineAdvance: PresentationFont.lineAdvance(style))
  }

  static func cameraDockWindowLevel(
    isCameraDock: Bool, style: CameraDockVisualStyle
  ) -> NSWindow.Level {
    guard isCameraDock, style == .attached else { return .floating }
    return NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
  }

  private static func cgRect(_ rect: CameraDockRect) -> CGRect {
    CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
  }

  @discardableResult func updateCameraDockPlacement(
    on display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    let priorSize = viewportSize
    guard applyCameraDockPresentation(on: display, preferences: preferences, style: style) else {
      return false
    }
    if priorSize != viewportSize {
      operatorController?.cameraDockResized(to: viewportSize)
    } else {
      operatorController?.render()
    }
    return true
  }

  @discardableResult func updateCameraDockPresentation(style: ReadingStyle) -> CGSize? {
    guard isCameraDock, let screen = window?.screen,
      let display = operatorController?.displayProvider().first(where: { $0.id == displayID })
        ?? operatorController?.displayDescriptor(on: screen),
      applyCameraDockPresentation(on: display, preferences: dockPreferences, style: style)
    else { return nil }
    return viewportSize
  }

  private func applyCameraDockPresentation(
    on display: DisplayDescriptor, preferences: CameraDockPreferences, style: ReadingStyle
  ) -> Bool {
    guard isCameraDock, let window,
      let geometry = Self.cameraDockLayout(
        display: display, preferences: preferences, style: style)
    else { return false }
    dockPreferences = preferences.normalized()
    dockLocation = geometry.placement.location
    dockStyle = geometry.style
    dockTopInset = CGFloat(geometry.contentTopInset)
    dockContentOffsetX = CGFloat(
      geometry.placement.contentFrame.minX - geometry.placement.frame.minX)
    dockLayout = geometry
    displayID = display.id
    displayUUID = display.preference.uuid ?? display.screen.localizedName
    window.setFrame(Self.cgRect(geometry.placement.frame), display: true)
    window.level = Self.cameraDockWindowLevel(isCameraDock: true, style: dockStyle)
    window.backgroundColor = .clear
    window.hasShadow = dockStyle == .detached
    root?.applyCameraDockLayout(
      geometry, topInset: dockTopInset, contentOffsetX: dockContentOffsetX,
      logicalSize: CGSize(width: geometry.viewportWidth, height: geometry.viewportHeight))
    root?.reflection.layer?.cornerRadius = 0
    applyCameraDockTextPanelVisibility(style: style)
    return true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    if !isCameraDock { operatorController?.floatingResized() }
    saveFrame()
  }
  func windowDidMove(_ notification: Notification) { saveFrame() }
  func windowDidChangeScreen(_ notification: Notification) {
    if !isCameraDock, let screen = window?.screen {
      displayID = operatorController?.displayDescriptor(on: screen)?.id
    }
    if !isCameraDock { saveFrame() }
  }
  private func saveFrame() {
    guard !isCameraDock, ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] != "1",
      let window,
      let screen = window.screen
    else { return }
    let key =
      "floatingFrame-"
      + (DisplayDescriptor.all().first { $0.screen == screen }?.preference.uuid
        ?? screen.localizedName)
    UserDefaults.standard.set(
      NSStringFromRect(
        window.frame.offsetBy(dx: -screen.visibleFrame.minX, dy: -screen.visibleFrame.minY)),
      forKey: key)
  }
  func windowWillClose(_ notification: Notification) {
    reflection.viewport.driver?.stop()
    onClose?()
  }
}

@MainActor final class FloatingRoot: NSView {
  let reflection: ReflectionContainerView
  let grip: NSView
  let cameraDockControls: CameraDockControlsView?
  /// Camera Dock only: hosts the prompt strip, fades its top and bottom edges, and
  /// carries the reading emphasis overlay.
  let cameraDockContentClip = NSView()
  let cameraDockEmphasis = CameraDockEmphasisView()
  private let cameraDockEdgeFade = CAGradientLayer()
  let placement: PrompterPlacement
  weak var controller: OperatorWindowController?
  var logicalSize = CGSize(width: 800, height: 400) {
    didSet {
      needsLayout = true
      cameraDockShapeNeedsUpdate = true
    }
  }
  var cameraDockTopInset: CGFloat = 0 {
    didSet {
      needsLayout = true
      cameraDockShapeNeedsUpdate = true
    }
  }
  var cameraDockContentOffsetX: CGFloat = 0 {
    didSet {
      needsLayout = true
      cameraDockShapeNeedsUpdate = true
    }
  }
  private(set) var cameraDockLayout: CameraDockLayout? {
    didSet {
      needsLayout = true
      cameraDockShapeNeedsUpdate = true
    }
  }
  /// Test seam: `nil` follows the system Reduce Motion setting.
  var cameraDockReduceMotionOverride: Bool?
  private var tracking: NSTrackingArea?
  private let cameraDockMask = CAShapeLayer()
  private(set) var cameraDockStyle: CameraDockVisualStyle = .detached
  private(set) var cameraDockIsExpanded = true
  private(set) var cameraDockIsParked = false
  private(set) var cameraDockPlaybackActive = false
  private var cameraDockShapeNeedsUpdate = true
  private var cameraDockLastMaskSize = CGSize.zero
  private var cameraDockKeyViewLoopInstalled = false
  private var cameraDockKeyViewLoopInstallationScheduled = false
  static let cameraDockShapeAnimationKey = "cameraDockShape"
  static let cameraDockContentOpacityAnimationKey = "cameraDockContentOpacity"
  init(
    reflection: ReflectionContainerView, controller: OperatorWindowController,
    placement: PrompterPlacement = .floating,
    cameraDockStyle: CameraDockVisualStyle = .detached,
    cameraDockTopInset: CGFloat = 0,
    cameraDockContentOffsetX: CGFloat = 0,
    cameraDockLayout: CameraDockLayout? = nil
  ) {
    self.reflection = reflection
    self.controller = controller
    self.placement = placement
    self.cameraDockTopInset = cameraDockTopInset
    self.cameraDockContentOffsetX = cameraDockContentOffsetX
    self.cameraDockLayout = cameraDockLayout
    let content: NSView
    if placement == .cameraDock {
      let controls = CameraDockControlsView(controller: controller)
      cameraDockControls = controls
      content = controls
      let opaqueGrip = NSView()
      opaqueGrip.wantsLayer = true
      opaqueGrip.appearance = NSAppearance(named: .darkAqua)
      opaqueGrip.layer?.backgroundColor = Self.backgroundColor(cameraDockStyle).cgColor
      grip = opaqueGrip
    } else {
      cameraDockControls = nil
      content = NSHostingView(
        rootView: AnyView(FloatingGrip(state: controller.state, controller: controller)))
      let effectGrip = NSVisualEffectView()
      effectGrip.material = .hudWindow
      effectGrip.blendingMode = .withinWindow
      effectGrip.state = .active
      effectGrip.alphaValue = controller.session.state == .running ? 0 : 1
      effectGrip.appearance = NSAppearance(named: .darkAqua)
      if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
        effectGrip.wantsLayer = true
        effectGrip.layer?.backgroundColor =
          NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor
      }
      grip = effectGrip
    }
    content.translatesAutoresizingMaskIntoConstraints = false
    grip.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: grip.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: grip.trailingAnchor),
      content.topAnchor.constraint(equalTo: grip.topAnchor),
      content.bottomAnchor.constraint(equalTo: grip.bottomAnchor),
    ])
    super.init(frame: .zero)
    if placement == .cameraDock {
      cameraDockContentClip.wantsLayer = true
      cameraDockContentClip.layer?.masksToBounds = true
      cameraDockContentClip.addSubview(reflection)
      cameraDockContentClip.addSubview(cameraDockEmphasis)
      reflection.layerUsesCoreImageFilters = true
      let fade = CameraDockGeometry.edgeFadeFraction
      cameraDockEdgeFade.startPoint = CGPoint(x: 0.5, y: 0)
      cameraDockEdgeFade.endPoint = CGPoint(x: 0.5, y: 1)
      cameraDockEdgeFade.colors = [
        NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor,
        NSColor.clear.cgColor,
      ]
      cameraDockEdgeFade.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
      cameraDockContentClip.layer?.mask = cameraDockEdgeFade
      addSubview(cameraDockContentClip)
    } else {
      addSubview(reflection)
    }
    addSubview(grip)
    wantsLayer = true
    if placement == .cameraDock {
      cameraDockIsExpanded = cameraDockStyle == .detached
      applyCameraDockStyle(cameraDockStyle)
    } else {
      layer?.cornerRadius = 14
      layer?.masksToBounds = true
    }
  }
  required init?(coder: NSCoder) { fatalError("Use init(reflection:controller:)") }
  private static func backgroundColor(_ style: CameraDockVisualStyle) -> NSColor {
    switch style {
    case .attached: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    case .detached: NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1)
    }
  }
  private func applyCameraDockStyle(_ style: CameraDockVisualStyle) {
    guard placement == .cameraDock else { return }
    cameraDockStyle = style
    let color = Self.backgroundColor(style)
    wantsLayer = true
    layer?.backgroundColor = color.cgColor
    layer?.cornerRadius = style == .detached ? 14 : 0
    layer?.masksToBounds = false
    cameraDockMask.fillColor = NSColor.white.cgColor
    cameraDockMask.frame = layer?.bounds ?? bounds
    layer?.mask = cameraDockMask
    grip.wantsLayer = true
    grip.layer?.backgroundColor = color.cgColor
    if style == .detached {
      cameraDockIsExpanded = true
      cameraDockIsParked = false
    }
    cameraDockShapeNeedsUpdate = true
  }
  /// Applies one Core layout in a single step. Geometry changes (width, lines, nudge,
  /// display) resize the window, so the silhouette snaps to the new frame on the next
  /// layout pass; only state transitions animate.
  func applyCameraDockLayout(
    _ layout: CameraDockLayout, topInset: CGFloat, contentOffsetX: CGFloat,
    logicalSize: CGSize
  ) {
    guard placement == .cameraDock else { return }
    if cameraDockStyle != layout.style { applyCameraDockStyle(layout.style) }
    cameraDockTopInset = topInset
    cameraDockContentOffsetX = contentOffsetX
    cameraDockLayout = layout
    self.logicalSize = logicalSize
  }
  /// First presentation: an attached Dock unfurls from the housing chin into the open
  /// tray, so the operator sees where it lives before reading from it.
  func revealCameraDock() {
    guard placement == .cameraDock, cameraDockStyle == .attached else { return }
    cameraDockIsParked = false
    cameraDockIsExpanded = false
    updateCameraDockShape(animated: false)
    setCameraDockExpanded(true, animated: true)
  }
  func setCameraDockParked(_ parked: Bool, animated: Bool = true) {
    guard placement == .cameraDock, cameraDockStyle == .attached else { return }
    cameraDockIsParked = parked
    setCameraDockExpanded(!parked || cameraDockPlaybackActive, animated: animated)
  }
  func setCameraDockExpanded(_ expanded: Bool, animated: Bool = true) {
    guard placement == .cameraDock else { return }
    let shouldExpand = cameraDockStyle == .attached ? expanded : true
    guard cameraDockIsExpanded != shouldExpand else { return }
    cameraDockIsExpanded = shouldExpand
    updateCameraDockShape(animated: animated)
    refreshTrackingArea()
    needsLayout = true
  }
  /// Playback opens the Dock and tightens the tray to the text strip; pausing brings the
  /// controls band back. Both edges of the change animate.
  func updateCameraDockPlaybackState(_ active: Bool, animated: Bool = true) {
    guard placement == .cameraDock, cameraDockPlaybackActive != active else { return }
    cameraDockPlaybackActive = active
    if active { cameraDockIsParked = false }
    if active, !cameraDockIsExpanded {
      setCameraDockExpanded(true, animated: animated)
    } else {
      updateCameraDockShape(animated: animated)
    }
  }
  private var cameraDockReduceMotion: Bool {
    cameraDockReduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
  private var cameraDockControlsVisible: Bool { !cameraDockPlaybackActive }
  private func cameraDockPath(expanded: Bool) -> CGPath {
    let bounds = self.bounds
    guard cameraDockStyle == .attached, let layout = cameraDockLayout,
      let metrics = CameraDockGeometry.morphMetrics(for: layout, progress: expanded ? 1 : 0),
      bounds.width > 0, bounds.height > 0
    else {
      return CGPath(
        roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
    }
    return Self.attachedPath(
      metrics, in: bounds,
      frameOrigin: CGPoint(
        x: layout.placement.frame.minX, y: layout.placement.frame.minY))
  }
  /// One element sequence for every morph state, so Core Animation can interpolate the
  /// path. Counter-clockwise from the lower-left corner: rounded bottom corners, straight
  /// sides, and at the top edge two concave ears that flare outward along the display's
  /// top edge, so the surface reads as part of the housing rather than a box below it.
  static func attachedPath(
    _ metrics: CameraDockMorphMetrics, in bounds: CGRect, frameOrigin: CGPoint
  ) -> CGPath {
    func local(_ rect: CameraDockRect) -> CGRect {
      CGRect(
        x: bounds.minX + rect.minX - frameOrigin.x, y: bounds.minY + rect.minY - frameOrigin.y,
        width: rect.width, height: rect.height)
    }
    let tray = local(metrics.tray)
    let bottom = min(metrics.bottomCornerRadius, tray.width / 2, tray.height / 2)
    let ear = min(
      metrics.earRadius, max(0, tray.minX - bounds.minX), max(0, bounds.maxX - tray.maxX),
      max(0, tray.height - bottom))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: tray.minX + bottom, y: tray.minY))
    path.addLine(to: CGPoint(x: tray.maxX - bottom, y: tray.minY))
    path.addQuadCurve(
      to: CGPoint(x: tray.maxX, y: tray.minY + bottom),
      control: CGPoint(x: tray.maxX, y: tray.minY))
    path.addLine(to: CGPoint(x: tray.maxX, y: tray.maxY - ear))
    path.addQuadCurve(
      to: CGPoint(x: tray.maxX + ear, y: tray.maxY),
      control: CGPoint(x: tray.maxX, y: tray.maxY))
    path.addLine(to: CGPoint(x: tray.minX - ear, y: tray.maxY))
    path.addQuadCurve(
      to: CGPoint(x: tray.minX, y: tray.maxY - ear),
      control: CGPoint(x: tray.minX, y: tray.maxY))
    path.addLine(to: CGPoint(x: tray.minX, y: tray.minY + bottom))
    path.addQuadCurve(
      to: CGPoint(x: tray.minX + bottom, y: tray.minY),
      control: CGPoint(x: tray.minX, y: tray.minY))
    path.closeSubpath()
    return path
  }
  private func updateCameraDockShape(animated: Bool) {
    guard placement == .cameraDock, let layer, bounds.width > 0, bounds.height > 0 else { return }
    cameraDockShapeNeedsUpdate = false
    cameraDockLastMaskSize = bounds.size
    cameraDockMask.frame = layer.bounds
    let newPath = cameraDockPath(expanded: cameraDockIsExpanded)
    let fromPath =
      cameraDockMask.presentation()?.path
      ?? cameraDockMask.path
      ?? cameraDockPath(expanded: !cameraDockIsExpanded)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    cameraDockMask.path = newPath
    CATransaction.commit()
    // Attached, the controls sit in the camera band and stay with the pill; only the
    // prompt fades with the tray. Detached keeps its controls band under the text.
    let gripVisible =
      cameraDockStyle == .attached
      ? cameraDockControlsVisible : cameraDockIsExpanded && cameraDockControlsVisible
    let contentTargets: [(NSView, CGFloat)] = [
      (reflection, cameraDockIsExpanded ? 1 : 0), (grip, gripVisible ? 1 : 0),
    ]
    let shapeKey = Self.cameraDockShapeAnimationKey
    let opacityKey = Self.cameraDockContentOpacityAnimationKey
    guard animated, cameraDockStyle == .attached else {
      cameraDockMask.removeAnimation(forKey: shapeKey)
      for (view, alpha) in contentTargets {
        view.layer?.removeAnimation(forKey: opacityKey)
        view.alphaValue = alpha
      }
      window?.invalidateShadow()
      return
    }
    let reduceMotion = cameraDockReduceMotion
    let opening = cameraDockIsExpanded
    if reduceMotion {
      cameraDockMask.removeAnimation(forKey: shapeKey)
    } else {
      // Sapphire pacing: the empty surface snaps open first and the content resolves
      // after it; closing hides the content first and shrinks the surface afterwards.
      let spring = CASpringAnimation(keyPath: "path")
      spring.fromValue = fromPath
      spring.toValue = newPath
      spring.mass = CameraDockMotion.springMass
      spring.stiffness =
        opening ? CameraDockMotion.openSpringStiffness : CameraDockMotion.closeSpringStiffness
      spring.damping =
        opening ? CameraDockMotion.openSpringDamping : CameraDockMotion.closeSpringDamping
      spring.initialVelocity = opening ? CameraDockMotion.expandInitialVelocity : 0
      spring.duration = CameraDockMotion.shapeDuration(settling: spring.settlingDuration)
      if !opening {
        spring.beginTime =
          cameraDockMask.convertTime(CACurrentMediaTime(), from: nil)
          + CameraDockMotion.collapseShapeDelay
        spring.fillMode = .backwards
      }
      cameraDockMask.add(spring, forKey: shapeKey)
    }
    for (view, alpha) in contentTargets {
      let fromOpacity = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
      view.alphaValue = alpha
      guard Float(alpha) != fromOpacity else { continue }
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = fromOpacity
      fade.toValue = Float(alpha)
      let revealing = alpha > 0
      var delay = 0.0
      if reduceMotion {
        fade.duration = CameraDockMotion.reducedMotionContentDuration
      } else {
        fade.duration =
          revealing
          ? CameraDockMotion.expandContentDuration
          : CameraDockMotion.collapseContentDuration
        delay = revealing ? CameraDockMotion.expandContentDelay : 0
        if revealing, let layer = view.layer {
          fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
          fade.fillMode = .backwards
        }
      }
      fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      view.layer?.add(fade, forKey: opacityKey)
      if view === reflection, !reduceMotion {
        animateCameraDockBlur(revealing: revealing, delay: delay, duration: fade.duration)
      }
    }
    window?.invalidateShadow()
  }
  static let cameraDockBlurFilterName = "cameraDockBlur"
  static let cameraDockBlurAnimationKey = "cameraDockBlurRadius"
  /// Resolves the prompt from blurred to sharp as it fades in, and blurs it as it fades
  /// out. The filter is attached only for the animation's lifetime so playback never
  /// renders through Core Image.
  private func animateCameraDockBlur(revealing: Bool, delay: Double, duration: Double) {
    guard let layer = reflection.layer, let blur = CIFilter(name: "CIGaussianBlur") else {
      return
    }
    let radius = CameraDockMotion.contentBlurRadius
    blur.name = Self.cameraDockBlurFilterName
    blur.setValue(revealing ? 0 : radius, forKey: kCIInputRadiusKey)
    layer.filters = [blur]
    let animation = CABasicAnimation(
      keyPath: "filters.\(Self.cameraDockBlurFilterName).inputRadius")
    animation.fromValue = revealing ? radius : 0
    animation.toValue = revealing ? 0 : radius
    animation.duration = duration
    animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
    animation.fillMode = .backwards
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak layer] in
      guard let layer, layer.animation(forKey: Self.cameraDockBlurAnimationKey) == nil else {
        return
      }
      layer.filters = nil
    }
    layer.add(animation, forKey: Self.cameraDockBlurAnimationKey)
    CATransaction.commit()
  }
  var cameraDockMaskPath: CGPath? { cameraDockMask.path }
  var cameraDockShapeAnimation: CAAnimation? {
    cameraDockMask.animation(forKey: Self.cameraDockShapeAnimationKey)
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    if placement == .cameraDock, let path = cameraDockMask.path {
      let localPoint = convert(point, from: superview)
      guard path.contains(localPoint) else { return nil }
    }
    return super.hitTest(point)
  }
  override func layout() {
    super.layout()
    if placement == .cameraDock {
      let contentWidth = min(logicalSize.width, max(0, bounds.width - cameraDockContentOffsetX))
      let controlsInBand = cameraDockStyle == .attached && cameraDockTopInset > 0
      let gripHeight = controlsInBand ? cameraDockTopInset : min(44, bounds.height)
      // In the band the controls share the top inset; below the text they take 44 pt.
      let stripBottom = controlsInBand ? 0 : gripHeight
      let stripHeight = max(
        0, bounds.height - gripHeight - (controlsInBand ? 0 : cameraDockTopInset))
      cameraDockContentClip.frame = CGRect(
        x: cameraDockContentOffsetX, y: stripBottom, width: contentWidth, height: stripHeight)
      let strip = cameraDockContentClip.bounds
      reflection.frame = strip
      cameraDockEmphasis.frame = strip
      cameraDockEdgeFade.frame = strip
      cameraDockEmphasis.apply(
        readingLineTop: (cameraDockLayout?.guideFraction ?? 0) * logicalSize.height,
        lineAdvance: cameraDockLayout?.lineAdvance ?? 0, stripHeight: strip.height)
      if controlsInBand {
        // The controls share the camera band with the housing: close and play on the
        // left, status and the adjust menu on the right, inside the current silhouette.
        grip.frame = CGRect(
          x: 0, y: bounds.height - cameraDockTopInset, width: bounds.width,
          height: cameraDockTopInset)
        if let layout = cameraDockLayout, let housing = layout.cameraHousing,
          let metrics = CameraDockGeometry.morphMetrics(
            for: layout, progress: cameraDockIsExpanded ? 1 : 0)
        {
          let originX = layout.placement.frame.minX
          cameraDockControls?.bandLayout = CameraDockControlsView.BandLayout(
            housing: (housing.minX - originX)...(housing.maxX - originX),
            tray: (metrics.tray.minX - originX)...(metrics.tray.maxX - originX),
            compact: !cameraDockIsExpanded)
        }
      } else {
        cameraDockControls?.bandLayout = nil
        grip.frame = CGRect(
          x: cameraDockContentOffsetX, y: 0, width: contentWidth, height: gripHeight)
      }
      if cameraDockShapeNeedsUpdate || cameraDockLastMaskSize != bounds.size {
        updateCameraDockShape(animated: false)
      }
    } else {
      reflection.frame = bounds
      let height = controller?.state.contrastWarning.isEmpty == false ? 52.0 : 28.0
      grip.frame = CGRect(
        x: 0, y: max(0, bounds.height - height), width: bounds.width, height: height)
    }
    reflection.setBoundsSize(logicalSize)
    reflection.needsLayout = true
    if placement == .cameraDock {
      scheduleCameraDockKeyViewLoopInstallation()
    }
  }
  private func scheduleCameraDockKeyViewLoopInstallation() {
    guard !cameraDockKeyViewLoopInstalled, !cameraDockKeyViewLoopInstallationScheduled else {
      return
    }
    cameraDockKeyViewLoopInstallationScheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.cameraDockKeyViewLoopInstallationScheduled = false
      self.grip.layoutSubtreeIfNeeded()
      self.installCameraDockKeyViewLoopIfReady()
    }
  }
  private func installCameraDockKeyViewLoopIfReady() {
    guard !cameraDockKeyViewLoopInstalled,
      let controls = cameraDockControls,
      let window = window as? PresentationPanel,
      bounds.width > 0, grip.bounds.width > 0, grip.bounds.height > 0,
      controls.bounds.width > 0, controls.bounds.height > 0,
      controls.closeButton.frame.width > 0,
      controls.playbackButton.frame.width > 0,
      controls.adjustButton.frame.width > 0
    else { return }

    cameraDockKeyViewLoopInstalled = true
    window.recalculateKeyViewLoop()
    controls.closeButton.nextKeyView = controls.playbackButton
    controls.playbackButton.nextKeyView = controls.adjustButton
    controls.adjustButton.nextKeyView = controls.closeButton
    window.initialFirstResponder = controls.closeButton
    if window.isKeyWindow { _ = window.makeFirstResponder(controls.closeButton) }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    refreshTrackingArea()
  }
  private func refreshTrackingArea() {
    if let tracking { removeTrackingArea(tracking) }
    let rect: CGRect
    if placement == .cameraDock, cameraDockStyle == .attached, !cameraDockIsExpanded,
      let path = cameraDockMask.path
    {
      rect = path.boundingBoxOfPath.insetBy(dx: -8, dy: -6)
    } else {
      rect = bounds
    }
    let area = NSTrackingArea(
      rect: rect, options: [.activeAlways, .mouseEnteredAndExited], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) {
    if placement == .cameraDock {
      // Peek: a parked Dock opens under the pointer and closes again when it leaves.
      setCameraDockExpanded(true)
      return
    }
    grip.alphaValue = 1
  }
  override func mouseExited(with event: NSEvent) {
    if placement == .cameraDock {
      if cameraDockIsParked, !cameraDockPlaybackActive {
        setCameraDockExpanded(false)
      }
      return
    }
    grip.alphaValue = controller?.session.state == .running ? 0 : 1
  }
  func updateCameraDockControls() {
    cameraDockControls?.refresh()
    updateCameraDockPlaybackState(controller?.state.running ?? false)
  }
}
/// A static overlay that keeps the reading line at full brightness and dims the lines
/// above and below it. It never intercepts clicks.
@MainActor final class CameraDockEmphasisView: NSView {
  private(set) var bandRange: ClosedRange<Double> = 0...0
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
  override func makeBackingLayer() -> CALayer {
    let gradient = CAGradientLayer()
    gradient.startPoint = CGPoint(x: 0.5, y: 0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1)
    return gradient
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  /// `readingLineTop` is measured from the strip's top edge in flipped viewport
  /// coordinates; the gradient runs bottom-to-top in layer coordinates.
  func apply(readingLineTop: Double, lineAdvance: Double, stripHeight: Double) {
    guard let gradient = layer as? CAGradientLayer else { return }
    guard stripHeight > 0, lineAdvance > 0, readingLineTop.isFinite, lineAdvance.isFinite else {
      gradient.colors = nil
      gradient.locations = nil
      bandRange = 0...0
      return
    }
    let padding = CameraDockGeometry.emphasisBandPadding
    let soft = CameraDockGeometry.emphasisSoftness
    let dim = NSColor.black.withAlphaComponent(CameraDockGeometry.dimmedLineAlpha).cgColor
    let clear = NSColor.clear.cgColor
    let bandBottom = max(0, stripHeight - (readingLineTop + lineAdvance + padding))
    let bandTop = min(stripHeight, stripHeight - (readingLineTop - padding))
    bandRange = bandBottom...max(bandBottom, bandTop)
    func fraction(_ y: Double) -> NSNumber {
      NSNumber(value: min(1, max(0, y / stripHeight)))
    }
    gradient.colors = [dim, dim, clear, clear, dim, dim]
    gradient.locations = [
      0, fraction(bandBottom - soft), fraction(bandBottom), fraction(bandTop),
      fraction(bandTop + soft), 1,
    ]
  }
}

struct FloatingGrip: View {
  @ObservedObject var state: OperatorState
  unowned let controller: OperatorWindowController
  var body: some View {
    VStack(spacing: 2) {
      HStack {
        Button {
          controller.hideOutput()
        } label: {
          Image(systemName: "xmark")
        }.help("Stop Presenting · Escape").accessibilityLabel("Stop presenting")
        Image(systemName: "line.3.horizontal")
        Slider(value: $state.floatingOpacity, in: 0.3...1).onChange(of: state.floatingOpacity) {
          controller.updateFloatingOptions()
          controller.saveOperatorPreferences()
        }.accessibilityLabel("Whole window opacity")
        Button {
          controller.state.horizontal.toggle()
          controller.reflect()
        } label: {
          Image(systemName: "arrow.left.and.right")
        }.accessibilityLabel("Reflect horizontally")
        Button {
          controller.toggle()
        } label: {
          Image(systemName: state.running ? "pause.fill" : "play.fill")
          Text(state.running ? "Pause" : "Resume").font(.system(size: 11, weight: .medium))
        }.accessibilityLabel("Play or Pause · Space")
      }.buttonStyle(.borderless).controlSize(.small).frame(height: 28).padding(.horizontal, 6)
      if !state.contrastWarning.isEmpty { Text(state.contrastWarning).font(.caption2).lineLimit(2) }
    }.foregroundStyle(.primary)
  }
}

@MainActor struct CameraDockGrip {
  static let closeAccessibilityLabel = "Close Camera Dock"
  static let playbackAccessibilityLabel = "Play or pause"
  static let adjustAccessibilityLabel = "Adjust Camera Dock"

  let state: OperatorState
  unowned let controller: OperatorWindowController

  var canPlay: Bool {
    !controller.script.source.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var statusText: String {
    if controller.cameraDockCameraMayBeElsewhere {
      let status = controller.state.cameraDockReady ? "Ready" : state.running ? "Playing" : "Paused"
      return "\(status) · camera may be on another display"
    }
    if state.voiceActive && !state.voiceMessage.isEmpty { return state.voiceMessage }
    if controller.state.cameraDockReady {
      return canPlay ? "Ready · Space to play" : "Ready"
    }
    if state.running { return "Playing" }
    if controller.session.snapshot?.attributed.string.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    .isEmpty == true {
      return "Ready"
    }
    return controller.session.state == .idle ? "Ready" : "Paused · Space to resume"
  }
}

@MainActor final class CameraDockControlsView: NSView {
  weak var controller: OperatorWindowController?
  let closeButton = NSButton(frame: .zero)
  let playbackButton = NSButton(frame: .zero)
  let adjustButton = NSPopUpButton(frame: .zero, pullsDown: true)
  let statusLabel = NSTextField(labelWithString: "Ready")
  static let collapseMenuTitle = "Collapse to Notch"
  private(set) var collapseItem: NSMenuItem?
  /// Attached Camera Dock: the controls sit in the camera band on either side of the
  /// housing, within the current silhouette's horizontal range. Parked, the pill keeps
  /// only play and adjust at its ends.
  struct BandLayout: Equatable {
    var housing: ClosedRange<CGFloat>
    var tray: ClosedRange<CGFloat>
    var compact: Bool
  }
  var bandLayout: BandLayout? {
    didSet { if bandLayout != oldValue { needsLayout = true } }
  }

  var accessibilityControls: [NSView] { [closeButton, playbackButton, adjustButton] }

  init(controller: OperatorWindowController) {
    self.controller = controller
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    configure(
      closeButton, symbol: "xmark", label: CameraDockGrip.closeAccessibilityLabel,
      help: "Return to the previous presentation surface · Escape", action: #selector(closeDock))
    configure(
      playbackButton, symbol: "play.fill", label: CameraDockGrip.playbackAccessibilityLabel,
      help: "Play or pause · Space", action: #selector(togglePlayback))
    configureAdjustMenu()

    statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.setAccessibilityElement(false)

    closeButton.nextKeyView = playbackButton
    playbackButton.nextKeyView = adjustButton
    adjustButton.nextKeyView = closeButton
    for view in [closeButton, playbackButton, statusLabel, adjustButton] { addSubview(view) }
    setAccessibilityElement(false)
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("Use init(controller:)") }

  override func layout() {
    super.layout()
    if let band = bandLayout {
      layoutInBand(band)
      return
    }
    closeButton.isHidden = false
    statusLabel.isHidden = false
    let inset: CGFloat = min(6, max(0, bounds.width / 2))
    let gap: CGFloat = 6
    let buttonHeight: CGFloat = min(28, bounds.height)
    let buttonY = max(0, (bounds.height - buttonHeight) / 2)
    let available = max(0, bounds.width - inset * 2)
    let closeWidth = min(28, available)
    let playbackWidth = min(28, max(0, available - closeWidth - gap))
    let adjustWidth = min(32, max(0, available - closeWidth - playbackWidth - gap * 2))
    let closeX = inset
    let playbackX = closeX + closeWidth + gap
    let adjustX = bounds.width - inset - adjustWidth
    let statusX = playbackX + playbackWidth + gap
    let statusWidth = max(0, adjustX - gap - statusX)

    closeButton.frame = CGRect(x: closeX, y: buttonY, width: closeWidth, height: buttonHeight)
    playbackButton.frame = CGRect(
      x: playbackX, y: buttonY, width: playbackWidth, height: buttonHeight)
    statusLabel.frame = CGRect(
      x: statusX, y: buttonY, width: statusWidth, height: buttonHeight)
    adjustButton.frame = CGRect(x: adjustX, y: buttonY, width: adjustWidth, height: buttonHeight)
  }

  private func layoutInBand(_ band: BandLayout) {
    let edge: CGFloat = 10
    let gap: CGFloat = 6
    let buttonHeight: CGFloat = min(24, max(0, bounds.height - 6))
    let buttonY = max(0, (bounds.height - buttonHeight) / 2)
    let buttonWidth: CGFloat = 28
    let adjustWidth: CGFloat = 32
    let leftRoom = max(0, band.housing.lowerBound - band.tray.lowerBound - edge * 2)
    let rightRoom = max(0, band.tray.upperBound - band.housing.upperBound - edge * 2)
    // Every control gets a frame on every path. Close yields to Play when the band is too
    // narrow for both; Core reserves `controlsBandReserve` so the open tray never is.
    let showsClose = !band.compact && leftRoom >= buttonWidth * 2 + gap
    closeButton.isHidden = !showsClose
    statusLabel.isHidden = band.compact
    var leftX = band.tray.lowerBound + edge
    closeButton.frame = CGRect(
      x: leftX, y: buttonY, width: showsClose ? buttonWidth : 0, height: buttonHeight)
    if showsClose { leftX += buttonWidth + gap }
    let playbackWidth = min(buttonWidth, max(0, band.housing.lowerBound - edge - leftX))
    playbackButton.frame = CGRect(
      x: leftX, y: buttonY, width: playbackWidth, height: buttonHeight)
    let adjustVisibleWidth = min(adjustWidth, rightRoom)
    let adjustX = band.tray.upperBound - edge - adjustVisibleWidth
    adjustButton.frame = CGRect(
      x: adjustX, y: buttonY, width: adjustVisibleWidth, height: buttonHeight)
    let statusX = band.housing.upperBound + edge
    statusLabel.frame = CGRect(
      x: statusX, y: buttonY, width: max(0, adjustX - gap - statusX), height: buttonHeight)
  }

  private func configure(
    _ button: NSButton, symbol: String, label: String, help: String, action: Selector
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    button.title = ""
    button.bezelStyle = .texturedRounded
    button.controlSize = .small
    button.refusesFirstResponder = false
    button.setAccessibilityElement(true)
    button.setAccessibilityRole(.button)
    button.setAccessibilityLabel(label)
    button.setAccessibilityHelp(help)
    button.toolTip = help
    button.target = self
    button.action = action
  }

  private func configureAdjustMenu() {
    adjustButton.controlSize = .small
    adjustButton.refusesFirstResponder = false
    adjustButton.setAccessibilityElement(true)
    adjustButton.setAccessibilityRole(.popUpButton)
    adjustButton.setAccessibilityLabel(CameraDockGrip.adjustAccessibilityLabel)
    adjustButton.setAccessibilityHelp("Adjust Camera Dock width, visible lines, and position")
    adjustButton.toolTip = "Adjust Camera Dock width, visible lines, and horizontal position"
    adjustButton.addItem(withTitle: "Adjust")
    adjustButton.item(at: 0)?.image = NSImage(
      systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
    adjustButton.imagePosition = .imageOnly
    guard let menu = adjustButton.menu else { return }
    menu.addItem(NSMenuItem.separator())
    addMenuItem("Wider", to: menu, action: #selector(increaseWidth))
    addMenuItem("Narrower", to: menu, action: #selector(decreaseWidth))
    addMenuItem("Show More Lines", to: menu, action: #selector(increaseLineCount))
    addMenuItem("Show Fewer Lines", to: menu, action: #selector(decreaseLineCount))
    addMenuItem("Move Right", to: menu, action: #selector(nudgeRight))
    addMenuItem("Move Left", to: menu, action: #selector(nudgeLeft))
    menu.addItem(NSMenuItem.separator())
    addMenuItem("Reset Placement", to: menu, action: #selector(resetPlacement))
    collapseItem = addMenuItem(Self.collapseMenuTitle, to: menu, action: #selector(collapseToNotch))
  }

  @discardableResult
  private func addMenuItem(_ title: String, to menu: NSMenu, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return item
  }

  func refresh() {
    guard let controller else { return }
    let grip = CameraDockGrip(state: controller.state, controller: controller)
    statusLabel.stringValue = grip.statusText
    playbackButton.isEnabled = grip.canPlay
    playbackButton.image = NSImage(
      systemSymbolName: controller.state.running ? "pause.fill" : "play.fill",
      accessibilityDescription: CameraDockGrip.playbackAccessibilityLabel)
    collapseItem?.isEnabled = controller.cameraDock?.dockStyle == .attached
  }

  @objc private func closeDock() { controller?.hideOutput() }
  @objc private func togglePlayback() { controller?.toggle() }
  @objc private func increaseWidth() {
    guard let controller else { return }
    controller.setCameraDockWidth(controller.state.cameraDockWidth + 20)
  }
  @objc private func decreaseWidth() {
    guard let controller else { return }
    controller.setCameraDockWidth(controller.state.cameraDockWidth - 20)
  }
  @objc private func increaseLineCount() {
    guard let controller else { return }
    controller.setCameraDockLineCount(controller.state.cameraDockLineCount + 1)
  }
  @objc private func decreaseLineCount() {
    guard let controller else { return }
    controller.setCameraDockLineCount(controller.state.cameraDockLineCount - 1)
  }
  @objc private func nudgeRight() {
    guard let controller else { return }
    controller.setCameraDockHorizontalNudge(controller.state.cameraDockHorizontalNudge + 8)
  }
  @objc private func nudgeLeft() {
    guard let controller else { return }
    controller.setCameraDockHorizontalNudge(controller.state.cameraDockHorizontalNudge - 8)
  }
  @objc private func resetPlacement() { controller?.resetCameraDockPreferences() }
  @objc private func collapseToNotch() { controller?.cameraDock?.collapseToNotch() }
}
