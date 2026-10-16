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
  public let viewportWidth: Double
  public let viewportHeight: Double
  public let lineCount: Int
  public let isBuiltInDisplay: Bool
  public let style: CameraDockVisualStyle
  public let cameraSafeAreaHeight: Double
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
  public static let defaultWidthFraction = 0.44
  public static let detachedGap = 6.0
  public static let controlsHeight = 44.0
  public static let minimumLineCount = 2
  public static let maximumLineCount = 5
  public static let defaultLineCount = 3
  public static let minimumHorizontalNudge = -120.0
  public static let maximumHorizontalNudge = 120.0

  public static func defaultWidth(screenWidth: Double) -> Double {
    guard screenWidth.isFinite, screenWidth > 0 else { return minimumWidth }
    return min(maximumWidth, max(minimumWidth, screenWidth * defaultWidthFraction))
  }

  public static func viewportHeight(lineAdvance: Double, lineCount: Int) -> Double? {
    guard lineAdvance.isFinite, lineAdvance > 0,
      (minimumLineCount...maximumLineCount).contains(lineCount)
    else { return nil }
    return ceil(lineAdvance * (Double(lineCount) + 0.25) + 16)
  }

  public static func layout(
    on parameters: CameraDockScreenParameters, isBuiltIn: Bool, isMirrored: Bool = false,
    preferences: CameraDockPreferences, lineAdvance: Double
  ) -> CameraDockLayout? {
    let preferences = preferences.normalized()
    guard
      let viewportHeight = viewportHeight(
        lineAdvance: lineAdvance, lineCount: preferences.lineCount)
    else { return nil }
    let builtInTarget = isBuiltIn && !isMirrored
    guard
      let placement = placement(
        on: parameters, isBuiltIn: builtInTarget, width: preferences.width,
        height: viewportHeight + controlsHeight, horizontalNudge: preferences.horizontalNudge)
    else { return nil }
    return CameraDockLayout(
      screenParameters: parameters, placement: placement,
      viewportWidth: placement.contentFrame.width, viewportHeight: viewportHeight,
      lineCount: preferences.lineCount, isBuiltInDisplay: builtInTarget,
      style: placement.location == .camera ? .attached : .detached,
      cameraSafeAreaHeight: placement.location == .camera
        ? cameraSafeAreaHeight(on: parameters) : 0)
  }

  public static func cameraSafeAreaHeight(on parameters: CameraDockScreenParameters) -> Double {
    resolvedSafeTop(
      screenFrame: parameters.screenFrame, safeTop: parameters.safeTop,
      auxiliaryTopLeftArea: parameters.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: parameters.auxiliaryTopRightArea)
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

    var cameraHousing: CameraDockRect?
    if layout.style == .attached, layout.cameraSafeAreaHeight > 0 {
      let housing: CameraDockRect
      let safeEdge = screen.maxY - layout.cameraSafeAreaHeight
      func isUsableAuxiliaryArea(_ area: CameraDockRect) -> Bool {
        area.isFiniteAndPositive && area.isContained(in: screen, tolerance: 0.5)
          && area.minY >= safeEdge - 0.5
      }
      if let left = parameters.auxiliaryTopLeftArea,
        let right = parameters.auxiliaryTopRightArea,
        isUsableAuxiliaryArea(left), isUsableAuxiliaryArea(right), left.maxX < right.minX
      {
        housing = CameraDockRect(
          x: left.maxX, y: screen.maxY - layout.cameraSafeAreaHeight,
          width: right.minX - left.maxX, height: layout.cameraSafeAreaHeight)
      } else {
        let width = min(screen.width * 0.2, max(36, layout.cameraSafeAreaHeight * 4.5))
        housing = CameraDockRect(
          x: screen.midX - width / 2, y: screen.maxY - layout.cameraSafeAreaHeight,
          width: width, height: layout.cameraSafeAreaHeight)
      }
      guard let normalizedHousing = normalized(housing) else { return nil }
      cameraHousing = normalizedHousing
    }

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
      cameraHousing: cameraHousing, dock: dock, content: content, caption: caption)
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
    let fittedWidth = min(width, visibleFrame.width)
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
      if cameraSafeEdge <= visibleFrame.maxY + 0.5 {
        top = screenFrame.maxY
        panelTopInset = cameraSafeTop
        location = .camera
        // The safe edge keeps the panel below the housing. NSScreen's auxiliary areas refine
        // the horizontal anchor, but missing or inconsistent areas must not reject a safe fit.
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

  public init(width: Double, lineCount: Int = 3, horizontalNudge: Double = 0) {
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
  }

  public static func defaults(screenWidth: Double) -> Self {
    Self(width: CameraDockGeometry.defaultWidth(screenWidth: screenWidth))
  }

  public func normalized() -> Self {
    Self(width: width, lineCount: lineCount, horizontalNudge: horizontalNudge)
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
    return value.normalized()
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
