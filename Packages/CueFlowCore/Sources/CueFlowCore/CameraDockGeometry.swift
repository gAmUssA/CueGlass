import Foundation

public struct CameraDockRect: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var minX: Double { x }
  public var minY: Double { y }
  public var maxX: Double { x + width }
  public var maxY: Double { y + height }
  public var midX: Double { x + width / 2 }
  public var isFiniteAndPositive: Bool {
    x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
      && maxX.isFinite && maxY.isFinite
  }
  public func intersects(_ other: Self) -> Bool {
    minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
  }
  public func isContained(in other: Self, tolerance: Double = 0) -> Bool {
    minX >= other.minX - tolerance && minY >= other.minY - tolerance
      && maxX <= other.maxX + tolerance && maxY <= other.maxY + tolerance
  }
}

public enum CameraDockLocation: String, Codable, Sendable {
  case camera
  case topOfDisplay
}

public struct CameraDockPlacement: Equatable, Sendable {
  public let frame: CameraDockRect
  public let contentFrame: CameraDockRect
  public let anchorX: Double
  public let location: CameraDockLocation
}

public enum CameraDockVisualStyle: String, Equatable, Sendable {
  case attached
  case detached
}

public struct CameraDockScreenParameters: Equatable, Sendable {
  public let screenFrame: CameraDockRect
  public let visibleFrame: CameraDockRect
  public let safeTop: Double
  public let auxiliaryTopLeftArea: CameraDockRect?
  public let auxiliaryTopRightArea: CameraDockRect?

  public init(
    screenFrame: CameraDockRect, visibleFrame: CameraDockRect, safeTop: Double,
    auxiliaryTopLeftArea: CameraDockRect?, auxiliaryTopRightArea: CameraDockRect?
  ) {
    self.screenFrame = screenFrame
    self.visibleFrame = visibleFrame
    self.safeTop = safeTop
    self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
    self.auxiliaryTopRightArea = auxiliaryTopRightArea
  }
}

public struct CameraDockLayout: Equatable, Sendable {
  public let screenParameters: CameraDockScreenParameters
  public let placement: CameraDockPlacement
  public let cameraHousing: CameraDockRect?
  public let contentTopInset: Double
  public let viewportWidth: Double
  /// The prompt viewport height handed to the shared playback session: exactly
  /// `lineCount` lines plus the vertical padding.
  public let viewportHeight: Double
  /// The line pitch the viewport was sized for.
  public let lineAdvance: Double
  /// Fraction of the viewport height above the reading line, so the current line sits
  /// in the vertical centre of the strip with equal context above and below it. The
  /// presentation layer passes this as the viewport's guide fraction.
  public let guideFraction: Double
  public let lineCount: Int
  public let isBuiltInDisplay: Bool
  public let style: CameraDockVisualStyle
  public let cameraSafeAreaHeight: Double
}

/// The attached Camera Dock silhouette at one point of the compact-to-expanded morph.
/// `stem` fills the camera housing band; `tray` hangs below the safe edge. Both corner
/// radii and the concave shoulder fillets interpolate with `progress`, so paths built
/// from any two metrics share one element sequence and animate cleanly.
public struct CameraDockMorphMetrics: Equatable, Sendable {
  public let progress: Double
  public let stem: CameraDockRect
  public let tray: CameraDockRect
  public let outline: CameraDockRect
  public let topCornerRadius: Double
  public let bottomCornerRadius: Double
  public let shoulderRadius: Double
  public let contentOpacity: Double
}

/// Motion contract for the attached Camera Dock morph, paced after the Sapphire
/// reference: the empty black surface snaps open in roughly a quarter second, then the
/// content resolves from blurred to sharp; closing hides the content first and shrinks
/// the empty surface afterwards. The spring is settled, slightly under-damped
/// (damping ratio ≈ 0.85).
public enum CameraDockMotion {
  public static let springMass = 1.0
  public static let springStiffness = 450.0
  public static let springDamping = 36.0
  public static let expandInitialVelocity = 0.3
  public static let minimumShapeDuration = 0.3
  public static let maximumShapeDuration = 0.5
  /// Content starts resolving once the shape has mostly landed.
  public static let expandContentDelay = 0.16
  public static let expandContentDuration = 0.3
  public static let contentBlurRadius = 14.0
  public static let collapseContentDuration = 0.1
  /// The empty surface starts shrinking after the content has gone.
  public static let collapseShapeDelay = 0.08
  /// Reduce Motion keeps a short crossfade and skips the shape motion and blur.
  public static let reducedMotionContentDuration = 0.15

  /// Clamps a spring's estimated settling time into the perceptible, well-paced window.
  public static func shapeDuration(settling: Double) -> Double {
    guard settling.isFinite else { return minimumShapeDuration }
    return min(maximumShapeDuration, max(minimumShapeDuration, settling))
  }
}

public struct CameraDockPlacementMap: Equatable, Sendable {
  public let displayAspectRatio: Double
  public let style: CameraDockVisualStyle
  public let menuBarBand: CameraDockRect
  public let cameraHousing: CameraDockRect?
  public let dock: CameraDockRect
  public let content: CameraDockRect
  public let caption: String
}

public enum CameraDockGeometry {
  public static let minimumWidth = 360.0
  public static let maximumWidth = 760.0
  /// Keep the expanded Camera Dock close to Sapphire's focused, camera-width composition.
  public static let defaultWidthFraction = 0.38
  fileprivate static let previousDefaultWidthFraction = 0.44
  public static let detachedGap = 6.0
  public static let controlsHeight = 44.0
  public static let minimumLineCount = 2
  public static let maximumLineCount = 5
  public static let defaultLineCount = 3
  public static let minimumHorizontalNudge = -120.0
  public static let maximumHorizontalNudge = 120.0
  public static let estimatedNotchSafeAreaHeight = 37.0
  /// Margin kept above the first line and below the last line of the strip.
  public static let viewportVerticalPadding = 8.0

  /// Compact (parked) silhouette: a short chin under the housing with fully rounded
  /// lower corners and small shoulder fillets.
  public static let compactChinHeight = 14.0
  public static let compactChinOverhang = 14.0
  public static let compactBottomCornerRadius = 14.0
  public static let compactShoulderRadius = 8.0
  /// Expanded silhouette: a rounded tray hanging from the housing. The shoulders rise
  /// into the camera band beside the housing so the black surface blends with the
  /// housing's rounded corners; prompt content never enters that band.
  public static let expandedTopCornerRadius = 22.0
  public static let expandedBottomCornerRadius = 22.0
  public static let expandedShoulderRadius = 12.0
  /// Content fades in only once the tray has mostly opened.
  public static let contentFadeStartProgress = 0.45
  /// Reading emphasis inside the open tray: the line on the guide stays at full
  /// brightness, neighbouring lines dim to this alpha, and the strip's top and bottom
  /// edges fade over `edgeFadeFraction` of the visible height so lines enter and leave
  /// softly instead of being cut.
  public static let dimmedLineAlpha = 0.5
  public static let emphasisBandPadding = 4.0
  public static let emphasisSoftness = 6.0
  public static let edgeFadeFraction = 0.14
  /// The Dock's text column is wider than the stage default so more words fit per line.
  public static let textColumnFraction = 0.86

  public static func defaultWidth(screenWidth: Double) -> Double {
    guard screenWidth.isFinite, screenWidth > 0 else { return minimumWidth }
    return min(maximumWidth, max(minimumWidth, screenWidth * defaultWidthFraction))
  }

  /// Strip height: exactly `lineCount` lines plus the padding, in whole points so the
  /// panel frame survives AppKit's integral window frames.
  public static func viewportHeight(lineAdvance: Double, lineCount: Int) -> Double? {
    guard lineAdvance.isFinite, lineAdvance > 0,
      (minimumLineCount...maximumLineCount).contains(lineCount)
    else { return nil }
    return ceil(lineAdvance * Double(lineCount) + viewportVerticalPadding * 2)
  }

  /// Offset of the reading line's top edge from the strip's top edge: the current line
  /// is centred, so the space above equals the space below it.
  public static func readingLineTop(viewportHeight: Double, lineAdvance: Double) -> Double {
    guard viewportHeight.isFinite, lineAdvance.isFinite, viewportHeight > lineAdvance,
      lineAdvance > 0
    else { return 0 }
    return (viewportHeight - lineAdvance) / 2
  }

  public static func guideFraction(viewportHeight: Double, lineAdvance: Double) -> Double {
    guard viewportHeight.isFinite, viewportHeight > 0 else { return 0 }
    return readingLineTop(viewportHeight: viewportHeight, lineAdvance: lineAdvance)
      / viewportHeight
  }

  public static func layout(
    on parameters: CameraDockScreenParameters, isBuiltIn: Bool, isMirrored: Bool = false,
    preferences: CameraDockPreferences, lineAdvance: Double
  ) -> CameraDockLayout? {
    let preferences = preferences.normalized()
    let builtInTarget = isBuiltIn && !isMirrored
    let reportedSafeTop = cameraSafeAreaHeight(on: parameters)
    let effectiveSafeTop: Double
    if builtInTarget, preferences.forceNotchAttachment == true {
      effectiveSafeTop = max(reportedSafeTop, estimatedNotchSafeAreaHeight)
    } else if builtInTarget, preferences.forceNotchAttachment == false {
      effectiveSafeTop = 0
    } else {
      effectiveSafeTop = reportedSafeTop
    }
    let disablesNotchInference = builtInTarget && preferences.forceNotchAttachment == false
    let effectiveParameters = CameraDockScreenParameters(
      screenFrame: parameters.screenFrame, visibleFrame: parameters.visibleFrame,
      safeTop: effectiveSafeTop,
      auxiliaryTopLeftArea: disablesNotchInference ? nil : parameters.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: disablesNotchInference ? nil : parameters.auxiliaryTopRightArea)
    guard
      let viewportHeight = viewportHeight(
        lineAdvance: lineAdvance, lineCount: preferences.lineCount)
    else { return nil }
    guard
      let placement = placement(
        on: effectiveParameters, isBuiltIn: builtInTarget, width: preferences.width,
        height: viewportHeight + controlsHeight, horizontalNudge: preferences.horizontalNudge)
    else { return nil }
    let attached = placement.location == .camera
    let safeAreaHeight = attached ? cameraSafeAreaHeight(on: effectiveParameters) : 0
    let menuBarHeight = max(0, parameters.screenFrame.maxY - parameters.visibleFrame.maxY)
    let contentTopInset = attached ? max(safeAreaHeight, menuBarHeight) : 0
    return CameraDockLayout(
      screenParameters: effectiveParameters, placement: placement,
      cameraHousing: attached ? cameraHousingFrame(on: effectiveParameters) : nil,
      contentTopInset: contentTopInset,
      viewportWidth: placement.contentFrame.width, viewportHeight: viewportHeight,
      lineAdvance: lineAdvance,
      guideFraction: guideFraction(viewportHeight: viewportHeight, lineAdvance: lineAdvance),
      lineCount: preferences.lineCount, isBuiltInDisplay: builtInTarget,
      style: placement.location == .camera ? .attached : .detached,
      cameraSafeAreaHeight: safeAreaHeight)
  }

  public static func cameraSafeAreaHeight(on parameters: CameraDockScreenParameters) -> Double {
    resolvedSafeTop(
      screenFrame: parameters.screenFrame, safeTop: parameters.safeTop,
      auxiliaryTopLeftArea: parameters.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: parameters.auxiliaryTopRightArea)
  }

  public static func cameraHousingFrame(
    on parameters: CameraDockScreenParameters
  ) -> CameraDockRect? {
    let screen = parameters.screenFrame
    let safeAreaHeight = cameraSafeAreaHeight(on: parameters)
    guard screen.isFiniteAndPositive, safeAreaHeight > 0 else { return nil }
    let safeEdge = screen.maxY - safeAreaHeight
    func isUsableAuxiliaryArea(_ area: CameraDockRect) -> Bool {
      area.isFiniteAndPositive && area.isContained(in: screen, tolerance: 0.5)
        && area.minY >= safeEdge - 0.5
    }
    if let left = parameters.auxiliaryTopLeftArea,
      let right = parameters.auxiliaryTopRightArea,
      isUsableAuxiliaryArea(left), isUsableAuxiliaryArea(right), left.maxX < right.minX
    {
      return CameraDockRect(
        x: left.maxX, y: safeEdge, width: right.minX - left.maxX, height: safeAreaHeight)
    }
    let width = min(screen.width * 0.2, max(36, safeAreaHeight * 4.5))
    return CameraDockRect(
      x: screen.midX - width / 2, y: safeEdge, width: width, height: safeAreaHeight)
  }

  /// The attached silhouette between the parked chin (`progress == 0`) and the open
  /// tray (`progress == 1`). With `controlsVisible == false` the open tray ends at the
  /// bottom of the prompt strip, so a playing Dock shows text only.
  public static func morphMetrics(
    for layout: CameraDockLayout, progress: Double, controlsVisible: Bool = true
  ) -> CameraDockMorphMetrics? {
    guard layout.style == .attached, let housing = layout.cameraHousing,
      progress.isFinite, layout.contentTopInset > 0
    else { return nil }
    let amount = min(1, max(0, progress))
    let screen = layout.screenParameters.screenFrame
    let stem = CameraDockRect(
      x: housing.x, y: screen.maxY - layout.contentTopInset,
      width: housing.width, height: layout.contentTopInset)
    let content = layout.placement.contentFrame
    let compactWidth = min(content.width, housing.width + compactChinOverhang * 2)
    let compactTray = CameraDockRect(
      x: housing.midX - compactWidth / 2,
      y: stem.minY - compactChinHeight, width: compactWidth, height: compactChinHeight)
    let expandedHeight = controlsVisible ? content.height : content.height - controlsHeight
    let expandedTray = CameraDockRect(
      x: content.x, y: content.maxY - expandedHeight, width: content.width,
      height: expandedHeight)
    func interpolate(_ start: Double, _ end: Double) -> Double {
      start + (end - start) * amount
    }
    let tray = CameraDockRect(
      x: interpolate(compactTray.x, expandedTray.x),
      y: interpolate(compactTray.y, expandedTray.y),
      width: interpolate(compactTray.width, expandedTray.width),
      height: interpolate(compactTray.height, expandedTray.height))
    let outline = CameraDockRect(
      x: min(stem.minX, tray.minX), y: min(stem.minY, tray.minY),
      width: max(stem.maxX, tray.maxX) - min(stem.minX, tray.minX),
      height: max(stem.maxY, tray.maxY) - min(stem.minY, tray.minY))
    let opacity = min(
      1, max(0, (amount - contentFadeStartProgress) / (1 - contentFadeStartProgress)))
    return CameraDockMorphMetrics(
      progress: amount, stem: stem, tray: tray, outline: outline,
      topCornerRadius: interpolate(0, expandedTopCornerRadius),
      bottomCornerRadius: interpolate(compactBottomCornerRadius, expandedBottomCornerRadius),
      shoulderRadius: interpolate(compactShoulderRadius, expandedShoulderRadius),
      contentOpacity: opacity)
  }

  public static func placementMap(
    for layout: CameraDockLayout, displayName: String, cameraMayBeElsewhere: Bool = false
  ) -> CameraDockPlacementMap? {
    let parameters = layout.screenParameters
    let screen = parameters.screenFrame
    let aspectRatio = screen.width / screen.height
    guard aspectRatio.isFinite, aspectRatio > 0 else { return nil }

    func normalized(_ rect: CameraDockRect) -> CameraDockRect? {
      guard rect.isFiniteAndPositive else { return nil }
      let result = CameraDockRect(
        x: (rect.minX - screen.minX) / screen.width,
        y: (rect.minY - screen.minY) / screen.height,
        width: rect.width / screen.width,
        height: rect.height / screen.height)
      return result.isFiniteAndPositive ? result : nil
    }

    let menuBarHeight = max(detachedGap / 3, screen.maxY - parameters.visibleFrame.maxY)
    guard
      let menuBarBand = normalized(
        CameraDockRect(
          x: screen.minX, y: screen.maxY - menuBarHeight,
          width: screen.width, height: menuBarHeight)),
      let dock = normalized(layout.placement.frame)
    else { return nil }
    guard let content = normalized(layout.placement.contentFrame) else { return nil }

    let label = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let display = label.isEmpty ? "Display" : label
    let type = layout.isBuiltInDisplay ? "Built-in" : "External"
    let placement =
      layout.style == .attached
      ? "notch integrated"
      : "top of display · camera position assumed"
    var caption = "CAMERA DOCK · \(type) \(display) · \(placement) · \(layout.lineCount) lines"
    if cameraMayBeElsewhere {
      caption += " · Your camera may be on another display"
    }

    return CameraDockPlacementMap(
      displayAspectRatio: aspectRatio, style: layout.style, menuBarBand: menuBarBand,
      cameraHousing: layout.cameraHousing.flatMap(normalized), dock: dock, content: content,
      caption: caption)
  }

  public static func placement(
    on parameters: CameraDockScreenParameters, isBuiltIn: Bool, width: Double, height: Double,
    horizontalNudge: Double
  ) -> CameraDockPlacement? {
    placement(
      screenFrame: parameters.screenFrame, visibleFrame: parameters.visibleFrame,
      safeTop: parameters.safeTop, auxiliaryTopLeftArea: parameters.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: parameters.auxiliaryTopRightArea, isBuiltIn: isBuiltIn,
      width: width, height: height, horizontalNudge: horizontalNudge)
  }

  public static func placement(
    screenFrame: CameraDockRect,
    visibleFrame: CameraDockRect,
    safeTop: Double,
    auxiliaryTopLeftArea: CameraDockRect?,
    auxiliaryTopRightArea: CameraDockRect?,
    isBuiltIn: Bool,
    width requestedWidth: Double,
    height: Double,
    horizontalNudge: Double
  ) -> CameraDockPlacement? {
    guard screenFrame.isFiniteAndPositive, visibleFrame.isFiniteAndPositive,
      visibleFrame.isContained(in: screenFrame, tolerance: 0.5), safeTop.isFinite,
      safeTop >= 0, safeTop <= screenFrame.height, requestedWidth.isFinite, height.isFinite,
      height > 0, horizontalNudge.isFinite
    else { return nil }
    guard visibleFrame.width >= minimumWidth, visibleFrame.height >= height else { return nil }

    let width = min(maximumWidth, max(minimumWidth, requestedWidth))
    // AppKit integralizes window frames; a fractional width would leave the mask path up
    // to a point narrower than the panel. Preferences keep their fractional value.
    let fittedWidth = min(width, visibleFrame.width).rounded(.down)
    let cameraSafeTop =
      isBuiltIn
      ? resolvedSafeTop(
        screenFrame: screenFrame, safeTop: safeTop,
        auxiliaryTopLeftArea: auxiliaryTopLeftArea,
        auxiliaryTopRightArea: auxiliaryTopRightArea)
      : 0
    let hasCameraSafeArea = cameraSafeTop > 0
    var location: CameraDockLocation = .topOfDisplay
    var anchorX = screenFrame.midX
    var top = visibleFrame.maxY - detachedGap
    var panelTopInset = 0.0

    if hasCameraSafeArea {
      let cameraSafeEdge = screenFrame.maxY - cameraSafeTop
      let menuBarInset = max(0, screenFrame.maxY - visibleFrame.maxY)
      top = screenFrame.maxY
      panelTopInset = max(cameraSafeTop, menuBarInset)
      location = .camera
      // Keep the tray below both the camera-safe edge and the visible menu-bar boundary.
      // The housing width remains the only part drawn through the top exclusion band.
      func isUsableAuxiliaryArea(_ area: CameraDockRect) -> Bool {
        area.isFiniteAndPositive && area.isContained(in: screenFrame, tolerance: 0.5)
          && area.minY >= cameraSafeEdge - 0.5
      }
      switch (auxiliaryTopLeftArea, auxiliaryTopRightArea) {
      case (.some(let left), .some(let right)):
        if isUsableAuxiliaryArea(left), isUsableAuxiliaryArea(right), left.maxX < right.minX {
          anchorX = left.maxX + (right.minX - left.maxX) / 2
        }
      default:
        break
      }
    }

    let panelHeight = height + panelTopInset
    guard top.isFinite, panelHeight.isFinite, top - panelHeight >= visibleFrame.minY else {
      return nil
    }
    let minimumX = visibleFrame.minX
    let maximumX = visibleFrame.maxX - fittedWidth
    let requestedX = anchorX - fittedWidth / 2 + horizontalNudge
    let x = min(maximumX, max(minimumX, requestedX))
    guard x.isFinite else { return nil }
    let frameX: Double
    let frameWidth: Double
    if location == .camera {
      let cameraCenteredX = anchorX - fittedWidth / 2
      let left = min(x, cameraCenteredX)
      let right = max(x + fittedWidth, cameraCenteredX + fittedWidth)
      frameX = max(visibleFrame.minX, left)
      frameWidth = min(visibleFrame.maxX, right) - frameX
    } else {
      frameX = x
      frameWidth = fittedWidth
    }
    let frame = CameraDockRect(
      x: frameX, y: top - panelHeight, width: frameWidth, height: panelHeight)
    let contentFrame = CameraDockRect(
      x: x, y: top - panelHeight, width: fittedWidth, height: height)
    let frameBoundary = location == .camera ? screenFrame : visibleFrame
    guard frame.isFiniteAndPositive, frame.isContained(in: frameBoundary, tolerance: 0.5),
      contentFrame.isFiniteAndPositive,
      contentFrame.isContained(in: visibleFrame, tolerance: 0.5)
    else {
      return nil
    }
    return CameraDockPlacement(
      frame: frame, contentFrame: contentFrame, anchorX: contentFrame.midX, location: location)
  }

  private static func resolvedSafeTop(
    screenFrame: CameraDockRect,
    safeTop: Double,
    auxiliaryTopLeftArea: CameraDockRect?,
    auxiliaryTopRightArea: CameraDockRect?
  ) -> Double {
    guard screenFrame.isFiniteAndPositive, safeTop.isFinite, safeTop >= 0,
      safeTop <= screenFrame.height
    else { return 0 }
    if safeTop > 0 { return safeTop }
    guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
      left.isFiniteAndPositive, right.isFiniteAndPositive,
      left.isContained(in: screenFrame, tolerance: 0.5),
      right.isContained(in: screenFrame, tolerance: 0.5), left.maxX < right.minX,
      abs(left.minY - right.minY) <= 0.5,
      abs(left.maxY - screenFrame.maxY) <= 0.5,
      abs(right.maxY - screenFrame.maxY) <= 0.5
    else { return 0 }
    let inferred = screenFrame.maxY - max(left.minY, right.minY)
    return inferred.isFinite && inferred > 0 && inferred <= 96 ? inferred : 0
  }
}

public struct CameraDockPreferences: Codable, Equatable, Sendable {
  public var width: Double
  public var lineCount: Int
  public var horizontalNudge: Double
  /// `true` opts into a centered notch attachment when screen geometry is missing.
  /// `nil` follows system geometry; `false` explicitly disables notch attachment.
  public var forceNotchAttachment: Bool?

  public init(
    width: Double, lineCount: Int = 3, horizontalNudge: Double = 0,
    forceNotchAttachment: Bool? = nil
  ) {
    self.width =
      width.isFinite
      ? min(CameraDockGeometry.maximumWidth, max(CameraDockGeometry.minimumWidth, width))
      : CameraDockGeometry.minimumWidth
    self.lineCount = min(
      CameraDockGeometry.maximumLineCount,
      max(CameraDockGeometry.minimumLineCount, lineCount))
    self.horizontalNudge =
      horizontalNudge.isFinite
      ? min(
        CameraDockGeometry.maximumHorizontalNudge,
        max(CameraDockGeometry.minimumHorizontalNudge, horizontalNudge))
      : 0
    self.forceNotchAttachment = forceNotchAttachment
  }

  public static func defaults(screenWidth: Double) -> Self {
    Self(width: CameraDockGeometry.defaultWidth(screenWidth: screenWidth))
  }

  public func normalized() -> Self {
    Self(
      width: width, lineCount: lineCount, horizontalNudge: horizontalNudge,
      forceNotchAttachment: forceNotchAttachment)
  }
}

public struct CameraDockPreferenceCatalog: Codable, Equatable, Sendable {
  private var values: [String: CameraDockPreferences] = [:]

  public init() {}

  public func preference(forDisplayUUID uuid: String, screenWidth: Double)
    -> CameraDockPreferences
  {
    guard !uuid.isEmpty, let value = values[uuid] else {
      return .defaults(screenWidth: screenWidth)
    }
    let normalized = value.normalized()
    let oldDefault = min(
      CameraDockGeometry.maximumWidth,
      max(
        CameraDockGeometry.minimumWidth,
        screenWidth * CameraDockGeometry.previousDefaultWidthFraction))
    let migrationTolerance = max(2, screenWidth * 0.005)
    guard abs(normalized.width - oldDefault) <= migrationTolerance else { return normalized }
    return CameraDockPreferences(
      width: CameraDockGeometry.defaultWidth(screenWidth: screenWidth),
      lineCount: normalized.lineCount, horizontalNudge: normalized.horizontalNudge,
      forceNotchAttachment: normalized.forceNotchAttachment)
  }

  public mutating func set(_ preference: CameraDockPreferences, forDisplayUUID uuid: String) {
    guard !uuid.isEmpty else { return }
    values[uuid] = preference.normalized()
  }
}

public struct CameraDockDisplayCandidate: Equatable, Sendable {
  public let id: String
  public let isBuiltIn: Bool
  public let isMirrored: Bool

  public init(id: String, isBuiltIn: Bool, isMirrored: Bool) {
    self.id = id
    self.isBuiltIn = isBuiltIn
    self.isMirrored = isMirrored
  }
}

public enum CameraDockDisplaySelection {
  public static func preferred(
    in displays: [CameraDockDisplayCandidate], selectedID: String
  ) -> String? {
    if let builtIn = displays.first(where: { $0.isBuiltIn && !$0.isMirrored }) {
      return builtIn.id
    }
    return displays.first(where: { $0.id == selectedID && !$0.isBuiltIn })?.id
  }

  public static func menuTitle(isBuiltIn: Bool, isMirrored: Bool, safeTop: Double) -> String {
    isBuiltIn && !isMirrored && safeTop.isFinite && safeTop > 0
      ? "Camera Dock" : "Camera Dock (top of display)"
  }
}
