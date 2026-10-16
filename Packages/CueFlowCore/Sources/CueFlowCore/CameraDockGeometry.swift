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
  public let anchorX: Double
  public let location: CameraDockLocation
}

public enum CameraDockGeometry {
  public static let minimumWidth = 360.0
  public static let maximumWidth = 760.0
  public static let defaultWidthFraction = 0.44
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
    let hasCameraSafeArea = isBuiltIn && safeTop > 0
    let location: CameraDockLocation = hasCameraSafeArea ? .camera : .topOfDisplay
    var anchorX = screenFrame.midX
    var top = visibleFrame.maxY

    if hasCameraSafeArea {
      top = screenFrame.maxY - safeTop
      guard top <= visibleFrame.maxY + 0.5 else { return nil }
      switch (auxiliaryTopLeftArea, auxiliaryTopRightArea) {
      case (.some(let left), .some(let right)):
        guard left.isFiniteAndPositive, right.isFiniteAndPositive,
          left.isContained(in: screenFrame, tolerance: 0.5),
          right.isContained(in: screenFrame, tolerance: 0.5), left.minY >= top - 0.5,
          right.minY >= top - 0.5, left.maxX < right.minX
        else { return nil }
        anchorX = left.maxX + (right.minX - left.maxX) / 2
      case (.none, .none):
        break
      default:
        return nil
      }
    }

    guard top.isFinite, top - height >= visibleFrame.minY else { return nil }
    let minimumX = visibleFrame.minX
    let maximumX = visibleFrame.maxX - fittedWidth
    let requestedX = anchorX - fittedWidth / 2 + horizontalNudge
    let x = min(maximumX, max(minimumX, requestedX))
    guard x.isFinite else { return nil }
    let frame = CameraDockRect(x: x, y: top - height, width: fittedWidth, height: height)
    guard frame.isFiniteAndPositive, frame.isContained(in: visibleFrame, tolerance: 0.5) else {
      return nil
    }
    return CameraDockPlacement(frame: frame, anchorX: frame.midX, location: location)
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
    return displays.first(where: { $0.id == selectedID })?.id
  }
}
