import Foundation
import Testing

@testable import CueFlowCore

@Test func cameraDockGeometryUsesNotchedSafeAreaAndHousingCenter() {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 0, y: 950, width: 650, height: 32)
  let right = CameraDockRect(x: 862, y: 950, width: 650, height: 32)
  let placement = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 32,
    auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, isBuiltIn: true,
    width: 665.28, height: 220, horizontalNudge: 0)

  #expect(placement?.location == .camera)
  #expect(placement?.anchorX == 756)
  #expect(placement?.frame.x == 423.5)
  #expect(placement?.frame.width == 665)
  #expect(placement?.frame.maxY == 982)
  #expect(placement?.contentFrame.maxY == 950)
  #expect(placement?.frame.isContained(in: screen) == true)
  #expect(placement?.contentFrame.isContained(in: visible) == true)
  #expect(
    placement?.contentFrame.intersects(CameraDockRect(x: 650, y: 950, width: 212, height: 32))
      == false)
}

@Test func cameraDockFallsBackToVisibleTopCenterOnNegativeOriginDisplay() {
  let screen = CameraDockRect(x: -1920, y: -50, width: 1920, height: 1080)
  let visible = CameraDockRect(x: -1920, y: 0, width: 1920, height: 1030)
  let placement = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: 760, height: 180, horizontalNudge: 0)

  #expect(placement?.location == .topOfDisplay)
  #expect(placement?.anchorX == -960)
  #expect(placement?.frame.maxY == 1024)
  #expect(placement?.frame.isContained(in: visible) == true)
}

@Test func cameraDockBuiltInWithoutSafeInsetUsesVisibleTopCenter() {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let placement = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 665.28, height: 180, horizontalNudge: 0)

  #expect(placement?.location == .topOfDisplay)
  #expect(placement?.frame.maxY == 944)
  #expect(placement?.anchorX == 756)
  #expect(placement?.frame.isContained(in: visible, tolerance: 0.5) == true)
}

@Test func cameraDockUsesAuxiliaryTopAreasWhenSafeInsetIsMissing() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 862, y: 950, width: 650, height: 32))

  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 2), lineAdvance: 40))
  let map = try #require(
    CameraDockGeometry.placementMap(for: layout, displayName: "Retina Display"))

  #expect(layout.style == .attached)
  #expect(layout.placement.frame.maxY == 982)
  #expect(layout.placement.contentFrame.maxY == 950)
  #expect(map.cameraHousing?.height == 32.0 / 982)
  #expect(map.caption.contains("notch integrated"))
  #expect(CameraDockGeometry.cameraSafeAreaHeight(on: parameters) == 32)
  #expect(
    CameraDockDisplaySelection.menuTitle(
      isBuiltIn: true, isMirrored: false,
      safeTop: CameraDockGeometry.cameraSafeAreaHeight(on: parameters)) == "Camera Dock")
}

@Test func cameraDockCanJoinNotchWhenBuiltInDisplayOmitsNotchGeometry() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(
        width: 665, lineCount: 2, forceNotchAttachment: true), lineAdvance: 40))
  let housing = try #require(layout.cameraHousing)
  let map = try #require(
    CameraDockGeometry.placementMap(for: layout, displayName: "Built-in Retina Display"))

  #expect(layout.style == .attached)
  #expect(layout.cameraSafeAreaHeight == CameraDockGeometry.estimatedNotchSafeAreaHeight)
  #expect(layout.placement.frame.maxY == parameters.screenFrame.maxY)
  #expect(housing.width == layout.cameraSafeAreaHeight * 4.5)
  #expect(housing.midX == parameters.screenFrame.midX)
  #expect(map.cameraHousing != nil)
  #expect(map.caption.contains("notch integrated"))
}

@Test func cameraDockMorphMetricsKeepAContinuousStemAndInterpolateTheTray() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 656, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 856, y: 950, width: 656, height: 32))
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40))
  let compact = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 0))
  let middle = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 0.5))
  let expanded = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 1))
  let playing = try #require(
    CameraDockGeometry.morphMetrics(for: layout, progress: 1, controlsVisible: false))
  let content = layout.placement.contentFrame
  let housing = try #require(layout.cameraHousing)

  // The stem always fills the housing band from the safe edge to the display top.
  for metrics in [compact, middle, expanded, playing] {
    #expect(metrics.stem.x == housing.x && metrics.stem.width == 200)
    #expect(metrics.stem.maxY == parameters.screenFrame.maxY)
    #expect(metrics.stem.minY == content.maxY)
    #expect(metrics.outline.maxY == parameters.screenFrame.maxY)
    #expect(metrics.tray.maxY == content.maxY)
    #expect(metrics.tray.isContained(in: content, tolerance: 1e-9))
  }
  // Parked: a short chin, centred on the housing, barely wider than it, fully rounded.
  #expect(compact.tray.height == CameraDockGeometry.compactChinHeight)
  #expect(compact.tray.width == 200 + CameraDockGeometry.compactChinOverhang * 2)
  #expect(abs(compact.tray.midX - housing.midX) < 1e-9)
  #expect(compact.topCornerRadius == 0)
  #expect(compact.bottomCornerRadius == CameraDockGeometry.compactBottomCornerRadius)
  #expect(compact.shoulderRadius == CameraDockGeometry.compactShoulderRadius)
  #expect(compact.contentOpacity == 0)
  // Midway: every quantity is the linear midpoint, so a path animation between the
  // endpoints passes through this silhouette.
  #expect(middle.tray.width == (compact.tray.width + content.width) / 2)
  #expect(middle.tray.minY == (compact.tray.minY + content.minY) / 2)
  #expect(middle.topCornerRadius == CameraDockGeometry.expandedTopCornerRadius / 2)
  #expect(middle.bottomCornerRadius == 18)
  #expect(middle.shoulderRadius == 10)
  #expect(middle.contentOpacity > 0 && middle.contentOpacity < 0.1)
  // Open with controls: the whole content frame. Open while playing: text strip only.
  #expect(expanded.tray == content)
  #expect(expanded.topCornerRadius == CameraDockGeometry.expandedTopCornerRadius)
  #expect(expanded.bottomCornerRadius == CameraDockGeometry.expandedBottomCornerRadius)
  #expect(expanded.shoulderRadius == CameraDockGeometry.expandedShoulderRadius)
  #expect(expanded.contentOpacity == 1)
  #expect(playing.tray.height == content.height - CameraDockGeometry.controlsHeight)
  #expect(playing.tray.height == layout.viewportHeight)
  #expect(playing.tray.width == content.width)
  #expect(CameraDockGeometry.morphMetrics(for: layout, progress: .nan) == nil)
  #expect(CameraDockGeometry.morphMetrics(for: layout, progress: 2)?.progress == 1)
  #expect(CameraDockGeometry.morphMetrics(for: layout, progress: -1)?.progress == 0)
}

@Test func cameraDockPlacementWidthsAreWholePoints() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1024, height: 768)
  let visible = CameraDockRect(x: 0, y: 0, width: 1024, height: 736)
  for requested in [389.12, 574.56, 665.28, 360.5, 759.9] {
    let placement = try #require(
      CameraDockGeometry.placement(
        screenFrame: screen, visibleFrame: visible, safeTop: 32,
        auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 736, width: 412, height: 32),
        auxiliaryTopRightArea: CameraDockRect(x: 612, y: 736, width: 412, height: 32),
        isBuiltIn: true, width: requested, height: 180, horizontalNudge: 0))
    #expect(placement.contentFrame.width == requested.rounded(.down))
    #expect(placement.frame.width == placement.frame.width.rounded())
    #expect(abs(placement.contentFrame.midX - 512) < 1e-9)
  }
  // The stored preference keeps its fractional default; only the placement rounds.
  #expect(abs(CameraDockPreferences.defaults(screenWidth: 1024).width - 389.12) < 1e-9)
}

@Test func cameraDockMorphMetricsAreAbsentForDetachedLayouts() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: false,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40))
  #expect(layout.style == .detached)
  #expect(layout.viewportHeight == 96)
  #expect(layout.placement.contentFrame.height == 96 + CameraDockGeometry.controlsHeight)
  #expect(CameraDockGeometry.morphMetrics(for: layout, progress: 1) == nil)
}

@Test func cameraDockAttachmentOverrideIsBackwardCompatibleAndCanDisableInference() throws {
  let oldPreferences = Data(#"{"width":600,"lineCount":2,"horizontalNudge":0}"#.utf8)
  let decoded = try JSONDecoder().decode(CameraDockPreferences.self, from: oldPreferences)
  #expect(decoded.forceNotchAttachment == nil)

  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 656, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 856, y: 950, width: 656, height: 32))
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2, forceNotchAttachment: false),
      lineAdvance: 40))
  #expect(layout.style == .detached)
  #expect(layout.cameraHousing == nil)
}

@Test func cameraDockDoesNotInferNotchFromIncompleteOrMisalignedAuxiliaryAreas() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 0, y: 950, width: 650, height: 32)
  let right = CameraDockRect(x: 862, y: 949, width: 650, height: 32)
  let singleSide = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: left, auxiliaryTopRightArea: nil)
  let misalignedPair = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right)

  #expect(CameraDockGeometry.cameraSafeAreaHeight(on: singleSide) == 0)
  #expect(CameraDockGeometry.cameraSafeAreaHeight(on: misalignedPair) == 0)
  #expect(
    CameraDockGeometry.layout(
      on: singleSide, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40)?.style
      == .detached)
  #expect(
    CameraDockGeometry.layout(
      on: misalignedPair, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40)?.style
      == .detached)
}

@Test func cameraDockFallbackSelectionAndLabelUseSelectedExternalDisplay() {
  let candidates = [
    CameraDockDisplayCandidate(id: "mirror", isBuiltIn: true, isMirrored: true),
    CameraDockDisplayCandidate(id: "external", isBuiltIn: false, isMirrored: false),
  ]
  let selected = CameraDockDisplaySelection.preferred(in: candidates, selectedID: "external")

  #expect(selected == "external")
  #expect(CameraDockDisplaySelection.preferred(in: candidates, selectedID: "mirror") == nil)
  #expect(CameraDockDisplaySelection.preferred(in: candidates, selectedID: "missing") == nil)
  #expect(
    CameraDockDisplaySelection.menuTitle(isBuiltIn: false, isMirrored: false, safeTop: 0)
      == "Camera Dock (top of display)")
  #expect(
    CameraDockDisplaySelection.menuTitle(isBuiltIn: true, isMirrored: false, safeTop: 32)
      == "Camera Dock")
  #expect(
    CameraDockDisplaySelection.menuTitle(isBuiltIn: true, isMirrored: true, safeTop: 32)
      == "Camera Dock (top of display)")
}

@Test func cameraDockRecomputesFromChangedScreenParameters() {
  let first = CameraDockGeometry.placement(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 862, y: 950, width: 650, height: 32),
    isBuiltIn: true, width: 665.28, height: 220, horizontalNudge: 0)
  let changed = CameraDockGeometry.placement(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1117),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1079), safeTop: 38,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 1079, width: 700, height: 38),
    auxiliaryTopRightArea: CameraDockRect(x: 1028, y: 1079, width: 700, height: 38),
    isBuiltIn: true, width: 760, height: 220, horizontalNudge: 0)

  #expect(first?.frame.maxY == 982)
  #expect(first?.contentFrame.maxY == 950)
  #expect(first?.anchorX == 756)
  #expect(changed?.frame.maxY == 1117)
  #expect(changed?.contentFrame.maxY == 1079)
  #expect(changed?.anchorX == 864)
  #expect(changed?.frame.width == 760)
  #expect(
    changed?.frame.isContained(in: CameraDockRect(x: 0, y: 0, width: 1728, height: 1117)) == true)
}

@Test func cameraDockGeometryClampsWidthAndHorizontalNudge() {
  let screen = CameraDockRect(x: -800, y: 0, width: 800, height: 800)
  let visible = CameraDockRect(x: -800, y: 0, width: 800, height: 760)
  let leftEdge = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 359, height: 150, horizontalNudge: -20_000)
  let rightEdge = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 761, height: 150, horizontalNudge: 20_000)

  #expect(leftEdge?.frame.width == 360)
  #expect(leftEdge?.frame.minX == -800)
  #expect(rightEdge?.frame.width == 760)
  #expect(rightEdge?.frame.maxX == 0)
  #expect(leftEdge?.frame.isContained(in: visible) == true)
  #expect(rightEdge?.frame.isContained(in: visible) == true)
}

@Test func cameraDockNeverIntersectsHousingAtWidthAndNudgeLimits() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 0, y: 950, width: 650, height: 32)
  let right = CameraDockRect(x: 862, y: 950, width: 650, height: 32)
  let housing = CameraDockRect(x: 650, y: 950, width: 212, height: 32)
  for (requestedWidth, nudge) in [
    (760.0, -120.0), (760.0, 120.0), (761.0, -200.0),
    (359.0, 200.0),
  ] {
    let placement = try #require(
      CameraDockGeometry.placement(
        screenFrame: screen, visibleFrame: visible, safeTop: 32,
        auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, isBuiltIn: true,
        width: requestedWidth, height: 220, horizontalNudge: nudge))
    #expect(placement.contentFrame.width >= 360 && placement.contentFrame.width <= 760)
    #expect(placement.frame.width >= placement.contentFrame.width)
    #expect(placement.frame.maxY == screen.maxY)
    #expect(placement.contentFrame.maxY == visible.maxY)
    #expect(placement.frame.isContained(in: screen, tolerance: 0.5))
    #expect(placement.contentFrame.isContained(in: visible, tolerance: 0.5))
    #expect(placement.frame.isContained(in: housing) || housing.isContained(in: placement.frame))
    #expect(!placement.contentFrame.intersects(housing))
    #expect(placement.frame.x.isFinite && placement.frame.y.isFinite)
    #expect(placement.frame.width.isFinite && placement.frame.height.isFinite)
  }
}

@Test func cameraDockLayoutUsesAttachedAndDetachedPlacementRules() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let notchedParameters = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950),
    safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 862, y: 950, width: 650, height: 32))
  let notched = try #require(
    CameraDockGeometry.layout(
      on: notchedParameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 3), lineAdvance: 40))

  #expect(notched.style == .attached)
  #expect(notched.placement.frame.maxY == 982)
  #expect(notched.placement.contentFrame.maxY == 950)
  #expect(notched.placement.anchorX == 756)
  #expect(notched.viewportWidth == notched.placement.contentFrame.width)
  #expect(notched.viewportHeight == 136)
  #expect(notched.lineAdvance == 40)
  #expect(abs(notched.guideFraction - 48.0 / 136.0) < 1e-12)
  #expect(notched.placement.contentFrame.height == 136 + CameraDockGeometry.controlsHeight)
  #expect(notched.cameraSafeAreaHeight == 32)

  let fallbackParameters = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950),
    safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
  let builtInFallback = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 3), lineAdvance: 40))
  let externalFallback = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: false,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 3), lineAdvance: 40))

  #expect(builtInFallback.style == .detached)
  #expect(externalFallback.style == .detached)
  #expect(builtInFallback.placement.frame.maxY == 944)
  #expect(externalFallback.placement.frame.maxY == 944)
}

@Test func cameraDockPlacementMapUsesLiveDockFrameAndNotchedDisplayDetails() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: -1920, y: -50, width: 1920, height: 1080),
    visibleFrame: CameraDockRect(x: -1920, y: -50, width: 1920, height: 1048), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: -1920, y: 998, width: 820, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: -900, y: 998, width: 900, height: 32))
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 760, lineCount: 3), lineAdvance: 40))
  let map = try #require(
    CameraDockGeometry.placementMap(for: layout, displayName: "Retina Display"))

  #expect(map.displayAspectRatio == 1920.0 / 1080.0)
  #expect(map.menuBarBand.x == 0)
  #expect(map.menuBarBand.y == 1048.0 / 1080.0)
  #expect(map.menuBarBand.width == 1)
  #expect(map.menuBarBand.height == 32.0 / 1080.0)
  #expect(map.cameraHousing != nil)
  #expect(map.cameraHousing?.x == 820.0 / 1920.0)
  #expect(map.cameraHousing?.width == 200.0 / 1920.0)
  #expect(map.dock.x == (layout.placement.frame.x + 1920) / 1920)
  #expect(map.dock.y == (layout.placement.frame.y + 50) / 1080)
  #expect(map.dock.width == layout.placement.frame.width / 1920)
  #expect(map.dock.height == layout.placement.frame.height / 1080)
  #expect(map.caption == "CAMERA DOCK · Built-in Retina Display · notch integrated · 3 lines")
  #expect(map.content.width == layout.placement.contentFrame.width / 1920)
}

@Test func cameraDockPlacementMapCaptionsNoInsetAndExternalFallbacks() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
  let preferences = CameraDockPreferences(width: 665.28, lineCount: 3)
  let builtInLayout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true, preferences: preferences, lineAdvance: 40))
  let externalLayout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: false, preferences: preferences, lineAdvance: 40))
  let builtInMap = try #require(
    CameraDockGeometry.placementMap(for: builtInLayout, displayName: "Retina Display"))
  let externalMap = try #require(
    CameraDockGeometry.placementMap(
      for: externalLayout, displayName: "Studio Display", cameraMayBeElsewhere: true))

  #expect(builtInMap.cameraHousing == nil)
  #expect(externalMap.cameraHousing == nil)
  #expect(
    builtInMap.caption
      == "CAMERA DOCK · Built-in Retina Display · top of display · camera position assumed · 3 lines"
  )
  #expect(
    externalMap.caption
      == "CAMERA DOCK · External Studio Display · top of display · camera position assumed · 3 lines · Your camera may be on another display"
  )
}

@Test func cameraDockPlacementMapRetainsEstimatedHousingWithMalformedAuxiliaryAreas() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 900, y: 950, width: 700, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 0, y: 950, width: 700, height: 32))
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40))
  let map = try #require(
    CameraDockGeometry.placementMap(for: layout, displayName: "Retina Display"))

  #expect(layout.style == .attached)
  #expect(map.cameraHousing != nil)
  #expect(map.cameraHousing?.x == (1512.0 / 2 - 72) / 1512)
  #expect(map.caption.contains("notch integrated"))
}

@Test func cameraDockGeometryRejectsMalformedAndTooSmallInputs() {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 0, y: 950, width: 900, height: 32)
  let overlappingRight = CameraDockRect(x: 800, y: 950, width: 712, height: 32)
  let valid = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 32,
    auxiliaryTopLeftArea: left, auxiliaryTopRightArea: overlappingRight, isBuiltIn: true,
    width: 600, height: 200, horizontalNudge: 0)
  let nonFinite = CameraDockGeometry.placement(
    screenFrame: CameraDockRect(x: .nan, y: 0, width: 1512, height: 982),
    visibleFrame: visible, safeTop: 32, auxiliaryTopLeftArea: nil,
    auxiliaryTopRightArea: nil, isBuiltIn: true, width: 600, height: 200,
    horizontalNudge: 0)
  let insetConsumesScreen = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 982,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 600, height: 200, horizontalNudge: 0)
  let tooNarrow = CameraDockGeometry.placement(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 359, height: 800),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 359, height: 760), safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: 360, height: 150, horizontalNudge: 0)

  #expect(valid?.location == .camera)
  #expect(valid?.anchorX == screen.midX)
  #expect(nonFinite == nil)
  #expect(insetConsumesScreen == nil)
  #expect(tooNarrow == nil)
  #expect(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: nil, isBuiltIn: true,
      width: 600, height: 200, horizontalNudge: 0)?.anchorX == screen.midX)
}

@Test func cameraDockCentersSafePlacementWhenAuxiliaryAreasAreReversed() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 862, y: 950, width: 650, height: 32)
  let right = CameraDockRect(x: 0, y: 950, width: 650, height: 32)

  #expect(left.isFiniteAndPositive)
  #expect(right.isFiniteAndPositive)
  #expect(left.isContained(in: screen, tolerance: 0.5))
  #expect(right.isContained(in: screen, tolerance: 0.5))
  #expect(!left.intersects(right))
  let placement = try #require(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, isBuiltIn: true,
      width: 600, height: 200, horizontalNudge: 0))

  #expect(placement.location == .camera)
  #expect(placement.anchorX == screen.midX)
  #expect(placement.frame.maxY == screen.maxY)
  #expect(placement.contentFrame.maxY == visible.maxY)
}

@Test func cameraDockKeepsSafeAreaPlacementWhenAuxiliaryAreasAreIncomplete() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let onlyLeft = CameraDockRect(x: 0, y: 950, width: 650, height: 32)
  let placement = try #require(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: onlyLeft, auxiliaryTopRightArea: nil, isBuiltIn: true,
      width: 665.28, height: 180, horizontalNudge: 0))

  #expect(placement.location == .camera)
  #expect(placement.anchorX == 756)
  #expect(placement.frame.maxY == 982)
  #expect(placement.contentFrame.maxY == 950)
  #expect(placement.frame.isContained(in: screen, tolerance: 0.5))
  #expect(placement.contentFrame.isContained(in: visible, tolerance: 0.5))
  #expect(
    placement.contentFrame.intersects(CameraDockRect(x: 650, y: 950, width: 212, height: 32))
      == false)
}

@Test func cameraDockFitsTwoVisibleLinesAt32PointTextWithIncompleteAuxiliaryAreas() throws {
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: 32),
    auxiliaryTopRightArea: nil)
  let layout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 2), lineAdvance: 42))

  #expect(layout.style == .attached)
  #expect(layout.viewportHeight == 100)
  #expect(
    layout.placement.frame.height
      == layout.viewportHeight + CameraDockGeometry.controlsHeight + layout.contentTopInset)
  #expect(
    layout.placement.contentFrame.height
      == layout.viewportHeight + CameraDockGeometry.controlsHeight)
  #expect(layout.placement.anchorX == 756)
}

@Test func cameraDockUsesSafeScreenAnchorWhenAuxiliaryAreasAreMalformed() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 900, y: 950, width: 700, height: 32)
  let right = CameraDockRect(x: 0, y: 950, width: 700, height: 32)
  let placement = try #require(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, isBuiltIn: true,
      width: 665.28, height: 180, horizontalNudge: 0))

  #expect(placement.location == .camera)
  #expect(placement.anchorX == 756)
  #expect(placement.frame.maxY == 982)
  #expect(placement.contentFrame.maxY == 950)
  #expect(placement.frame.isContained(in: screen, tolerance: 0.5))
  #expect(placement.contentFrame.isContained(in: visible, tolerance: 0.5))
  #expect(
    placement.contentFrame.intersects(CameraDockRect(x: 650, y: 950, width: 212, height: 32))
      == false)
}

@Test func cameraDockGeometryRejectsTooShortAndMalformedDisplayParameters() {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let goodLeft = CameraDockRect(x: 0, y: 950, width: 650, height: 32)
  let goodRight = CameraDockRect(x: 862, y: 950, width: 650, height: 32)
  let tooShort = CameraDockGeometry.placement(
    screenFrame: screen,
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 200), safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: 600, height: 201, horizontalNudge: 0)
  let negativeInset = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: -1,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 600, height: 200, horizontalNudge: 0)
  let infiniteInset = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: .infinity,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
    width: 600, height: 200, horizontalNudge: 0)
  let infiniteWidth = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: .infinity, height: 200, horizontalNudge: 0)
  let infiniteNudge = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 0,
    auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: 600, height: 200, horizontalNudge: -.infinity)
  let negativeAuxiliary = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: visible, safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: -1),
    auxiliaryTopRightArea: goodRight, isBuiltIn: true,
    width: 600, height: 200, horizontalNudge: 0)
  let zeroVisible = CameraDockGeometry.placement(
    screenFrame: screen, visibleFrame: CameraDockRect(x: 0, y: 0, width: 0, height: 950),
    safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: false,
    width: 600, height: 200, horizontalNudge: 0)
  let malformedParameters = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: visible, safeTop: -1,
    auxiliaryTopLeftArea: goodLeft, auxiliaryTopRightArea: goodRight)
  let malformedPlacement = CameraDockGeometry.placement(
    on: malformedParameters, isBuiltIn: true, width: 600, height: 200, horizontalNudge: 0)

  #expect(tooShort == nil)
  #expect(negativeInset == nil)
  #expect(infiniteInset == nil)
  #expect(infiniteWidth == nil)
  #expect(infiniteNudge == nil)
  #expect(negativeAuxiliary?.location == .camera)
  #expect(negativeAuxiliary?.anchorX == screen.midX)
  #expect(zeroVisible == nil)
  #expect(malformedPlacement == nil)
}

@Test func cameraDockKeepsNotchStemAndTrayBelowTheMenuBarWhenSafeEdgeIsAboveIt() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let placement = try #require(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 24,
      auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil, isBuiltIn: true,
      width: 665.28, height: 180, horizontalNudge: 0))

  #expect(placement.location == .camera)
  #expect(placement.frame.maxY == screen.maxY)
  #expect(placement.contentFrame.maxY == visible.maxY)
  #expect(placement.frame.isContained(in: screen, tolerance: 0.5))
  #expect(placement.contentFrame.isContained(in: visible, tolerance: 0.5))
}

@Test func cameraDockPreferenceDefaultsAndBoundsAreStable() throws {
  #expect(CameraDockGeometry.defaultWidthFraction == 0.38)
  #expect(abs(CameraDockGeometry.defaultWidth(screenWidth: 1512) - 574.56) < 1e-9)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 1200) == 456)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 800) == 360)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 2400) == 760)
  #expect(
    abs(CameraDockPreferences.defaults(screenWidth: 1512).width - 574.56) < 1e-9)
  #expect(CameraDockPreferences(width: 360, lineCount: 2, horizontalNudge: 0).width == 360)
  #expect(CameraDockPreferences(width: 760, lineCount: 5, horizontalNudge: 0).lineCount == 5)
  #expect(
    CameraDockPreferences(width: 359, lineCount: 1, horizontalNudge: .nan)
      == CameraDockPreferences(width: 360, lineCount: 2, horizontalNudge: 0))
  #expect(CameraDockPreferences(width: 500, horizontalNudge: -1000).horizontalNudge == -120)
  #expect(CameraDockPreferences(width: 500, horizontalNudge: 1000).horizontalNudge == 120)
  #expect(CameraDockPreferences(width: 761, lineCount: 6).width == 760)
  #expect(CameraDockPreferences(width: 359, lineCount: 1).lineCount == 2)
  #expect(CameraDockGeometry.viewportHeight(lineAdvance: 40, lineCount: 3) == 136)
  #expect(CameraDockGeometry.viewportHeight(lineAdvance: 40, lineCount: 1) == nil)
}

@Test func cameraDockViewportCentresTheReadingLineAndShowsWholeLines() throws {
  // The strip holds exactly `lineCount` lines plus padding, and the reading line sits in
  // its vertical centre with equal context above and below, for every supported count.
  for lineCount in CameraDockGeometry.minimumLineCount...CameraDockGeometry.maximumLineCount {
    for lineAdvance in [24.0, 41.6, 83.2, 124.8] {
      let height = try #require(
        CameraDockGeometry.viewportHeight(lineAdvance: lineAdvance, lineCount: lineCount))
      let padding = CameraDockGeometry.viewportVerticalPadding * 2
      let needed = lineAdvance * Double(lineCount) + padding
      let top = CameraDockGeometry.readingLineTop(viewportHeight: height, lineAdvance: lineAdvance)
      let fraction = CameraDockGeometry.guideFraction(
        viewportHeight: height, lineAdvance: lineAdvance)
      let below = height - lineAdvance - top

      #expect(height >= needed - 1e-9)
      #expect(height < needed + 1)
      #expect(height == height.rounded())
      #expect(abs(top - below) < 1e-9)
      #expect(abs(fraction * height - top) < 1e-9)
      #expect(fraction > 0)
      #expect(fraction < 0.5)
    }
  }
  // Three lines at 40 pt: one full line above the reading line, one below, 8 pt margins.
  #expect(CameraDockGeometry.readingLineTop(viewportHeight: 136, lineAdvance: 40) == 48)
  #expect(CameraDockGeometry.readingLineTop(viewportHeight: .nan, lineAdvance: 40) == 0)
  #expect(CameraDockGeometry.readingLineTop(viewportHeight: 30, lineAdvance: 40) == 0)
  #expect(CameraDockGeometry.guideFraction(viewportHeight: 0, lineAdvance: 40) == 0)
}

@Test func cameraDockMotionDurationsStayPerceptibleAndBounded() {
  #expect(CameraDockMotion.shapeDuration(settling: 0.1) == CameraDockMotion.minimumShapeDuration)
  #expect(CameraDockMotion.shapeDuration(settling: 0.42) == 0.42)
  #expect(CameraDockMotion.shapeDuration(settling: 3) == CameraDockMotion.maximumShapeDuration)
  #expect(CameraDockMotion.shapeDuration(settling: .nan) == CameraDockMotion.minimumShapeDuration)
  // Sapphire pacing: the shape lands in well under half a second, the content resolves
  // right after it, and the whole open reads in about half a second.
  #expect(CameraDockMotion.minimumShapeDuration >= 0.25)
  #expect(CameraDockMotion.maximumShapeDuration <= 0.5)
  #expect(CameraDockMotion.expandContentDelay < CameraDockMotion.maximumShapeDuration)
  #expect(CameraDockMotion.expandContentDelay + CameraDockMotion.expandContentDuration <= 0.5)
  #expect(CameraDockMotion.collapseContentDuration <= CameraDockMotion.collapseShapeDelay + 0.05)
  #expect(CameraDockMotion.contentBlurRadius > 0)
  #expect(CameraDockMotion.reducedMotionContentDuration <= 0.2)
  // Damping ratio of the published spring stays slightly under critical: settled, not floppy.
  let ratio =
    CameraDockMotion.springDamping
    / (2 * (CameraDockMotion.springStiffness * CameraDockMotion.springMass).squareRoot())
  #expect(ratio > 0.7 && ratio < 1)
  // Estimated settling time of the published spring sits inside the duration window.
  let omega = (CameraDockMotion.springStiffness / CameraDockMotion.springMass).squareRoot()
  let settling = -log(0.001) / (ratio * omega)
  #expect(settling >= CameraDockMotion.minimumShapeDuration)
  #expect(settling <= CameraDockMotion.maximumShapeDuration)
}

@Test func cameraDockPreferenceCatalogPersistsByDisplayUUID() throws {
  var catalog = CameraDockPreferenceCatalog()
  catalog.set(
    CameraDockPreferences(width: 540, lineCount: 4, horizontalNudge: 18),
    forDisplayUUID: "display-stage")
  catalog.set(
    CameraDockPreferences(width: 420, lineCount: 2, horizontalNudge: -12),
    forDisplayUUID: "display-desk")
  let restored = try JSONDecoder().decode(
    CameraDockPreferenceCatalog.self, from: JSONEncoder().encode(catalog))

  #expect(
    restored.preference(forDisplayUUID: "display-stage", screenWidth: 1512)
      == CameraDockPreferences(width: 540, lineCount: 4, horizontalNudge: 18))
  #expect(
    restored.preference(forDisplayUUID: "display-desk", screenWidth: 1512)
      == CameraDockPreferences(width: 420, lineCount: 2, horizontalNudge: -12))
  #expect(
    restored.preference(forDisplayUUID: "new-display", screenWidth: 1512)
      == CameraDockPreferences.defaults(screenWidth: 1512))
}

@Test func cameraDockPreferenceCatalogMigratesOnlyThePreviousDefaultWidth() {
  var catalog = CameraDockPreferenceCatalog()
  catalog.set(
    CameraDockPreferences(width: 665.28, lineCount: 2, horizontalNudge: 8),
    forDisplayUUID: "legacy-default")
  catalog.set(
    CameraDockPreferences(width: 600, lineCount: 4, horizontalNudge: -16),
    forDisplayUUID: "custom-width")

  let migrated = catalog.preference(forDisplayUUID: "legacy-default", screenWidth: 1512)
  #expect(abs(migrated.width - 574.56) < 1e-9)
  #expect(migrated.lineCount == 2)
  #expect(migrated.horizontalNudge == 8)
  #expect(
    catalog.preference(forDisplayUUID: "custom-width", screenWidth: 1512)
      == CameraDockPreferences(width: 600, lineCount: 4, horizontalNudge: -16))
}

@Test func cameraDockDisplaySelectionUsesBuiltInUnlessMirrored() {
  let displays = [
    CameraDockDisplayCandidate(id: "external", isBuiltIn: false, isMirrored: false),
    CameraDockDisplayCandidate(id: "built-in-mirrored", isBuiltIn: true, isMirrored: true),
  ]
  #expect(CameraDockDisplaySelection.preferred(in: displays, selectedID: "external") == "external")
  #expect(CameraDockDisplaySelection.preferred(in: displays, selectedID: "missing") == nil)
  #expect(
    CameraDockDisplaySelection.preferred(
      in: [
        displays[0],
        CameraDockDisplayCandidate(id: "built-in", isBuiltIn: true, isMirrored: false),
      ], selectedID: "external") == "built-in")
}
