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
  #expect(placement?.frame.x == 423.36)
  #expect(placement?.frame.maxY == 950)
  #expect(placement?.frame.isContained(in: visible) == true)
  #expect(
    placement?.frame.intersects(CameraDockRect(x: 650, y: 950, width: 212, height: 32)) == false)
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
  #expect(placement?.frame.maxY == 1030)
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
  #expect(placement?.frame.maxY == 950)
  #expect(placement?.anchorX == 756)
  #expect(placement?.frame.isContained(in: visible, tolerance: 0.5) == true)
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

  #expect(first?.frame.maxY == 950)
  #expect(first?.anchorX == 756)
  #expect(changed?.frame.maxY == 1079)
  #expect(changed?.anchorX == 864)
  #expect(changed?.frame.width == 760)
  #expect(
    changed?.frame.isContained(in: CameraDockRect(x: 0, y: 0, width: 1728, height: 1079)) == true)
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
    #expect(placement.frame.width >= 360 && placement.frame.width <= 760)
    #expect(placement.frame.maxY <= screen.maxY - 32 + 0.5)
    #expect(!placement.frame.intersects(housing))
    #expect(placement.frame.isContained(in: visible, tolerance: 0.5))
    #expect(placement.frame.x.isFinite && placement.frame.y.isFinite)
    #expect(placement.frame.width.isFinite && placement.frame.height.isFinite)
  }
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

  #expect(valid == nil)
  #expect(nonFinite == nil)
  #expect(insetConsumesScreen == nil)
  #expect(tooNarrow == nil)
  #expect(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: nil, isBuiltIn: true,
      width: 600, height: 200, horizontalNudge: 0) == nil)
}

@Test func cameraDockGeometryRejectsReversedAuxiliaryAreas() {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 982)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 950)
  let left = CameraDockRect(x: 862, y: 950, width: 650, height: 32)
  let right = CameraDockRect(x: 0, y: 950, width: 650, height: 32)

  #expect(left.isFiniteAndPositive)
  #expect(right.isFiniteAndPositive)
  #expect(left.isContained(in: screen, tolerance: 0.5))
  #expect(right.isContained(in: screen, tolerance: 0.5))
  #expect(!left.intersects(right))
  #expect(
    CameraDockGeometry.placement(
      screenFrame: screen, visibleFrame: visible, safeTop: 32,
      auxiliaryTopLeftArea: left, auxiliaryTopRightArea: right, isBuiltIn: true,
      width: 600, height: 200, horizontalNudge: 0) == nil)
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
  #expect(negativeAuxiliary == nil)
  #expect(zeroVisible == nil)
  #expect(malformedPlacement == nil)
}

@Test func cameraDockPreferenceDefaultsAndBoundsAreStable() throws {
  #expect(CameraDockGeometry.defaultWidthFraction == 0.44)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 1512) == 665.28)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 1200) == 528)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 800) == 360)
  #expect(CameraDockGeometry.defaultWidth(screenWidth: 2400) == 760)
  #expect(
    CameraDockPreferences.defaults(screenWidth: 1512)
      == CameraDockPreferences(
        width: 665.28, lineCount: 3, horizontalNudge: 0))
  #expect(CameraDockPreferences(width: 360, lineCount: 2, horizontalNudge: 0).width == 360)
  #expect(CameraDockPreferences(width: 760, lineCount: 5, horizontalNudge: 0).lineCount == 5)
  #expect(
    CameraDockPreferences(width: 359, lineCount: 1, horizontalNudge: .nan)
      == CameraDockPreferences(width: 360, lineCount: 2, horizontalNudge: 0))
  #expect(CameraDockPreferences(width: 500, horizontalNudge: -1000).horizontalNudge == -120)
  #expect(CameraDockPreferences(width: 500, horizontalNudge: 1000).horizontalNudge == 120)
  #expect(CameraDockPreferences(width: 761, lineCount: 6).width == 760)
  #expect(CameraDockPreferences(width: 359, lineCount: 1).lineCount == 2)
  #expect(CameraDockGeometry.viewportHeight(lineAdvance: 40, lineCount: 3) == 146)
  #expect(CameraDockGeometry.viewportHeight(lineAdvance: 40, lineCount: 1) == nil)
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
