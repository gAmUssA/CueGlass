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
  #expect(placement?.frame.x == 423.5 - CameraDockGeometry.expandedEarRadius)
  #expect(placement?.frame.width == 665 + CameraDockGeometry.expandedEarRadius * 2)
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

  // No hardware housing: the island is drawn around an emulated one sized from the
  // display width, at least as tall as the menu bar, centred, and labelled honestly.
  let estimated = CameraDockGeometry.emulatedHousingSize(screenWidth: 1512)
  #expect(layout.style == .attached)
  #expect(layout.isEmulatedHousing)
  #expect(layout.cameraSafeAreaHeight == max(32, estimated.height))
  #expect(layout.placement.frame.maxY == parameters.screenFrame.maxY)
  #expect(abs(housing.width - estimated.width) < 1e-9)
  #expect(housing.midX == parameters.screenFrame.midX)
  #expect(map.cameraHousing != nil)
  #expect(map.caption.contains("notch island · camera position assumed"))
  #expect(!map.caption.contains("notch integrated"))
}

@Test func cameraDockEmulatedHousingScalesWithDisplayWidthWithinBounds() {
  let small = CameraDockGeometry.emulatedHousingSize(screenWidth: 1024)
  let reference = CameraDockGeometry.emulatedHousingSize(screenWidth: 1728)
  let large = CameraDockGeometry.emulatedHousingSize(screenWidth: 5120)
  #expect(small.width == 140 && small.height == 26)
  #expect(abs(reference.width - 185) < 1e-9 && abs(reference.height - 32) < 1e-9)
  #expect(large.width == 260 && large.height == 38)
  #expect(CameraDockGeometry.emulatedHousingSize(screenWidth: .nan).width == 160)
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
  let content = layout.placement.contentFrame
  let housing = try #require(layout.cameraHousing)

  let top = parameters.screenFrame.maxY
  // One surface from the display top: it covers the housing and the band around it.
  for metrics in [compact, middle, expanded] {
    #expect(metrics.tray.maxY == top)
    #expect(metrics.tray.minX <= housing.minX && metrics.tray.maxX >= housing.maxX)
    #expect(metrics.tray.minX >= content.minX && metrics.tray.maxX <= content.maxX)
    #expect(metrics.tray.minY >= content.minY)
    #expect(metrics.earRadius > 0 && metrics.bottomCornerRadius > 0)
    #expect(metrics.tray.minX - metrics.earRadius >= layout.placement.frame.minX)
    #expect(metrics.tray.maxX + metrics.earRadius <= layout.placement.frame.maxX)
  }
  // Parked: a pill from the display top to a short chin under the housing.
  #expect(compact.tray.minY == content.maxY - CameraDockGeometry.compactChinHeight)
  #expect(compact.tray.width == 200 + CameraDockGeometry.compactChinOverhang * 2)
  #expect(abs(compact.tray.midX - housing.midX) < 1e-9)
  #expect(compact.bottomCornerRadius == CameraDockGeometry.compactBottomCornerRadius)
  #expect(compact.earRadius == CameraDockGeometry.compactEarRadius)
  #expect(compact.contentOpacity == 0)
  // Midway: every quantity is the linear midpoint, so a path animation between the
  // endpoints passes through this silhouette.
  #expect(middle.tray.width == (compact.tray.width + content.width) / 2)
  #expect(middle.tray.minY == (compact.tray.minY + content.minY) / 2)
  #expect(
    middle.bottomCornerRadius
      == (CameraDockGeometry.compactBottomCornerRadius
        + CameraDockGeometry.expandedBottomCornerRadius) / 2)
  #expect(
    middle.earRadius
      == (CameraDockGeometry.compactEarRadius + CameraDockGeometry.expandedEarRadius) / 2)
  #expect(middle.contentOpacity > 0 && middle.contentOpacity < 0.1)
  // Open: the content frame extended to the display top; the controls live in the band.
  #expect(expanded.tray.minX == content.minX && expanded.tray.width == content.width)
  #expect(expanded.tray.minY == content.minY)
  #expect(expanded.bottomCornerRadius == CameraDockGeometry.expandedBottomCornerRadius)
  #expect(expanded.earRadius == CameraDockGeometry.expandedEarRadius)
  #expect(expanded.contentOpacity == 1)
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
      preferences: CameraDockPreferences(width: 600, lineCount: 2, forceNotchAttachment: false),
      lineAdvance: 40))
  #expect(layout.style == .detached)
  #expect(!layout.isEmulatedHousing)
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
  // Bad metadata never implies a hardware notch; the island falls back to emulation,
  // and the explicit opt-out gives the plain tray.
  for parameters in [singleSide, misalignedPair] {
    let island = CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2), lineAdvance: 40)
    #expect(island?.style == .attached)
    #expect(island?.isEmulatedHousing == true)
    let tray = CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 600, lineCount: 2, forceNotchAttachment: false),
      lineAdvance: 40)
    #expect(tray?.style == .detached)
  }
}

@Test func cameraDockFallbackSelectionAndLabelUseSelectedExternalDisplay() {
  let candidates = [
    CameraDockDisplayCandidate(id: "mirror", isBuiltIn: true, isMirrored: true),
    CameraDockDisplayCandidate(id: "external", isBuiltIn: false, isMirrored: false),
  ]
  let selected = CameraDockDisplaySelection.preferred(in: candidates, selectedID: "external")

  #expect(selected == "external")
  // ADR 0012: with no unmirrored built-in display, the selected display is the target,
  // the mirrored built-in one included.
  #expect(CameraDockDisplaySelection.preferred(in: candidates, selectedID: "mirror") == "mirror")
  #expect(CameraDockDisplaySelection.preferred(in: candidates, selectedID: "missing") == nil)
  // The island is the default everywhere; only the explicit opt-out is labelled.
  #expect(
    CameraDockDisplaySelection.menuTitle(isBuiltIn: false, isMirrored: false, safeTop: 0)
      == "Camera Dock")
  #expect(
    CameraDockDisplaySelection.menuTitle(
      isBuiltIn: false, isMirrored: false, safeTop: 0, islandEnabled: false)
      == "Camera Dock (top of display)")
  #expect(
    CameraDockDisplaySelection.menuTitle(
      isBuiltIn: true, isMirrored: false, safeTop: 32, islandEnabled: false)
      == "Camera Dock")
  #expect(
    CameraDockDisplaySelection.menuTitle(
      isBuiltIn: true, isMirrored: true, safeTop: 32, islandEnabled: false)
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
  #expect(changed?.frame.width == 760 + CameraDockGeometry.expandedEarRadius * 2)
  #expect(
    changed?.frame.isContained(in: CameraDockRect(x: 0, y: 0, width: 1728, height: 1117)) == true)
}

@Test func cameraDockOpenTrayReservesTheControlsBandAtMinimumWidthAndNudgeLimits() throws {
  // The housing is 212 pt wide (x 650…862); at the minimum width the text tray alone leaves
  // 74 pt per side, and a full nudge moves it off one side of the housing entirely.
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 950, width: 650, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 862, y: 950, width: 650, height: 32))
  let reserve = CameraDockGeometry.controlsBandReserve
  for nudge in [
    CameraDockGeometry.minimumHorizontalNudge, 0.0, CameraDockGeometry.maximumHorizontalNudge,
  ] {
    let layout = try #require(
      CameraDockGeometry.layout(
        on: parameters, isBuiltIn: true,
        preferences: CameraDockPreferences(
          width: CameraDockGeometry.minimumWidth, lineCount: 2, horizontalNudge: nudge),
        lineAdvance: 40))
    let housing = try #require(layout.cameraHousing)
    let content = layout.placement.contentFrame
    let open = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 1))
    // Text keeps its nudged tray; the black surface still covers the band beside the housing.
    #expect(abs(content.midX - (756 + nudge)) < 1e-9)
    #expect(open.tray.minX <= housing.minX - reserve)
    #expect(open.tray.maxX >= housing.maxX + reserve)
    #expect(open.tray.minX <= content.minX && open.tray.maxX >= content.maxX)
    #expect(open.tray.minX - open.earRadius >= layout.placement.frame.minX)
    #expect(open.tray.maxX + open.earRadius <= layout.placement.frame.maxX)
    #expect(layout.placement.frame.isContained(in: parameters.screenFrame))
    let parked = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 0))
    #expect(parked.tray.minX <= housing.minX - CameraDockGeometry.compactChinOverhang)
    #expect(parked.tray.maxX >= housing.maxX + CameraDockGeometry.compactChinOverhang)
  }
}

@Test func cameraDockParkedPillKeepsItsOverhangForAWiderHousingAtMinimumWidth() throws {
  // A 328 pt housing (x 700…1028) with the 360 pt minimum text width: the text tray alone
  // leaves 16 pt per side, less than the 52 pt overhang each parked control needs.
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1117),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1079), safeTop: 38,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 1079, width: 700, height: 38),
    auxiliaryTopRightArea: CameraDockRect(x: 1028, y: 1079, width: 700, height: 38))
  let overhang = CameraDockGeometry.compactChinOverhang
  let reserve = CameraDockGeometry.controlsBandReserve
  for nudge in [
    CameraDockGeometry.minimumHorizontalNudge, 0.0, CameraDockGeometry.maximumHorizontalNudge,
  ] {
    let layout = try #require(
      CameraDockGeometry.layout(
        on: parameters, isBuiltIn: true,
        preferences: CameraDockPreferences(
          width: CameraDockGeometry.minimumWidth, lineCount: 3, horizontalNudge: nudge),
        lineAdvance: 48))
    let housing = try #require(layout.cameraHousing)
    #expect(housing.width == 328)
    #expect(layout.placement.contentFrame.width == CameraDockGeometry.minimumWidth)
    let parked = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 0))
    #expect(parked.tray.minX == housing.minX - overhang, "nudge \(nudge)")
    #expect(parked.tray.maxX == housing.maxX + overhang, "nudge \(nudge)")
    #expect(parked.tray.minX - parked.earRadius >= layout.placement.frame.minX)
    #expect(parked.tray.maxX + parked.earRadius <= layout.placement.frame.maxX)
    let open = try #require(CameraDockGeometry.morphMetrics(for: layout, progress: 1))
    #expect(open.tray.minX <= housing.minX - reserve, "nudge \(nudge)")
    #expect(open.tray.maxX >= housing.maxX + reserve, "nudge \(nudge)")
    #expect(open.tray.minX <= parked.tray.minX && open.tray.maxX >= parked.tray.maxX)
  }
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
  #expect(notched.placement.contentFrame.height == 136)
  #expect(notched.cameraSafeAreaHeight == 32)

  let fallbackParameters = CameraDockScreenParameters(
    screenFrame: screen, visibleFrame: CameraDockRect(x: 0, y: 0, width: 1512, height: 950),
    safeTop: 0, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
  let plainTray = CameraDockPreferences(width: 665.28, lineCount: 3, forceNotchAttachment: false)
  let builtInFallback = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: true, preferences: plainTray, lineAdvance: 40))
  let externalFallback = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: false, preferences: plainTray, lineAdvance: 40))
  let builtInIsland = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: true,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 3), lineAdvance: 40))
  let externalIsland = try #require(
    CameraDockGeometry.layout(
      on: fallbackParameters, isBuiltIn: false,
      preferences: CameraDockPreferences(width: 665.28, lineCount: 3), lineAdvance: 40))

  #expect(builtInFallback.style == .detached)
  #expect(externalFallback.style == .detached)
  #expect(builtInFallback.placement.frame.maxY == 944)
  #expect(externalFallback.placement.frame.maxY == 944)
  // By default a display without a notch gets the emulated island instead.
  for island in [builtInIsland, externalIsland] {
    #expect(island.style == .attached)
    #expect(island.isEmulatedHousing)
    #expect(island.placement.frame.maxY == 982)
    #expect(island.contentTopInset == 32)
    #expect(island.placement.contentFrame.maxY == 950)
  }
  #expect(!notched.isEmulatedHousing)
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

  #expect(builtInMap.cameraHousing != nil)
  #expect(externalMap.cameraHousing != nil)
  #expect(
    builtInMap.caption
      == "CAMERA DOCK · Built-in Retina Display · notch island · camera position assumed · 3 lines"
  )
  #expect(
    externalMap.caption
      == "CAMERA DOCK · External Studio Display · notch island · camera position assumed · 3 lines · Your camera may be on another display"
  )
  // The opt-out keeps the earlier plain-tray captions.
  let plainTray = CameraDockPreferences(width: 665.28, lineCount: 3, forceNotchAttachment: false)
  let trayLayout = try #require(
    CameraDockGeometry.layout(
      on: parameters, isBuiltIn: true, preferences: plainTray, lineAdvance: 40))
  let trayMap = try #require(
    CameraDockGeometry.placementMap(for: trayLayout, displayName: "Retina Display"))
  #expect(trayMap.cameraHousing == nil)
  #expect(
    trayMap.caption
      == "CAMERA DOCK · Built-in Retina Display · top of display · camera position assumed · 3 lines"
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

  let estimatedWidth = CameraDockGeometry.emulatedHousingSize(screenWidth: 1512).width
  #expect(layout.style == .attached)
  #expect(!layout.isEmulatedHousing)
  #expect(map.cameraHousing != nil)
  #expect(abs((map.cameraHousing?.x ?? -1) - (1512.0 / 2 - estimatedWidth / 2) / 1512) < 1e-12)
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
  #expect(layout.placement.frame.height == layout.viewportHeight + layout.contentTopInset)
  #expect(layout.placement.contentFrame.height == layout.viewportHeight)
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
  // Sapphire pacing: the shape lands in well under a second, the content resolves right
  // after it, and the whole open reads in about half a second.
  #expect(CameraDockMotion.minimumShapeDuration >= 0.25)
  #expect(CameraDockMotion.maximumShapeDuration <= 0.6)
  #expect(CameraDockMotion.expandContentDelay < CameraDockMotion.maximumShapeDuration)
  #expect(CameraDockMotion.expandContentDelay + CameraDockMotion.expandContentDuration <= 0.5)
  #expect(CameraDockMotion.collapseContentDuration <= CameraDockMotion.collapseShapeDelay + 0.05)
  #expect(CameraDockMotion.contentBlurRadius > 0)
  #expect(CameraDockMotion.reducedMotionContentDuration <= 0.2)
  // Opening overshoots a little (damping fraction ≈ 0.6); closing does not (≈ 1).
  func ratio(_ stiffness: Double, _ damping: Double) -> Double {
    damping / (2 * (stiffness * CameraDockMotion.springMass).squareRoot())
  }
  let openRatio = ratio(CameraDockMotion.openSpringStiffness, CameraDockMotion.openSpringDamping)
  let closeRatio = ratio(
    CameraDockMotion.closeSpringStiffness, CameraDockMotion.closeSpringDamping)
  #expect(openRatio > 0.5 && openRatio < 0.75)
  #expect(closeRatio > 0.9 && closeRatio < 1.05)
  // Response times: open ≈ 0.4 s, close ≈ 0.3 s.
  let openResponse = 2 * Double.pi / CameraDockMotion.openSpringStiffness.squareRoot()
  let closeResponse = 2 * Double.pi / CameraDockMotion.closeSpringStiffness.squareRoot()
  #expect(abs(openResponse - 0.4) < 0.01)
  #expect(abs(closeResponse - 0.3) < 0.01)
  // Whatever the clamp cuts off is invisible: residual amplitude below 2 % at the cutoff.
  let openOmega = CameraDockMotion.openSpringStiffness.squareRoot()
  let residual = exp(-openRatio * openOmega * CameraDockMotion.maximumShapeDuration)
  #expect(residual < 0.02)
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

/// A catalog as a build before the 0.38 default wrote it: entries only, no marker.
private func legacyCameraDockCatalog(_ json: String) throws -> CameraDockPreferenceCatalog {
  try JSONDecoder().decode(CameraDockPreferenceCatalog.self, from: Data(json.utf8))
}

@Test func cameraDockPreferenceCatalogMigratesOnlyThePreviousDefaultWidth() throws {
  let catalog = try legacyCameraDockCatalog(
    """
    {"values":{
      "legacy-default":{"width":665.28,"lineCount":2,"horizontalNudge":8},
      "custom-width":{"width":600,"lineCount":4,"horizontalNudge":-16}
    }}
    """)

  let migrated = catalog.preference(forDisplayUUID: "legacy-default", screenWidth: 1512)
  #expect(abs(migrated.width - 574.56) < 1e-9)
  #expect(migrated.lineCount == 2)
  #expect(migrated.horizontalNudge == 8)
  #expect(
    catalog.preference(forDisplayUUID: "custom-width", screenWidth: 1512)
      == CameraDockPreferences(width: 600, lineCount: 4, horizontalNudge: -16))
}

@Test func cameraDockPreferenceCatalogKeepsWidthsSavedByTheCurrentBuild() throws {
  var catalog = CameraDockPreferenceCatalog()
  // Slider stops that fall within the migration tolerance of the old 44 % default.
  let chosen: [(uuid: String, width: Double, screenWidth: Double)] = [
    ("laptop-1728", 760, 1728), ("laptop-1710", 760, 1710), ("laptop-1512", 660, 1512),
    ("laptop-1470", 640, 1470), ("laptop-1440", 640, 1440),
  ]
  for entry in chosen {
    catalog.set(
      CameraDockPreferences(width: entry.width, lineCount: 4, horizontalNudge: 12),
      forDisplayUUID: entry.uuid)
  }
  let restored = try JSONDecoder().decode(
    CameraDockPreferenceCatalog.self, from: JSONEncoder().encode(catalog))

  for entry in chosen {
    let expected = CameraDockPreferences(width: entry.width, lineCount: 4, horizontalNudge: 12)
    #expect(
      catalog.preference(forDisplayUUID: entry.uuid, screenWidth: entry.screenWidth) == expected,
      "\(entry.uuid) was rewritten before saving")
    #expect(
      restored.preference(forDisplayUUID: entry.uuid, screenWidth: entry.screenWidth)
        == expected, "\(entry.uuid) was rewritten after reopening")
  }
}

@Test func cameraDockPreferenceCatalogMigratesLegacyEntriesBesideCurrentOnes() throws {
  var catalog = try legacyCameraDockCatalog(
    """
    {"values":{
      "legacy-1728":{"width":760.32,"lineCount":3,"horizontalNudge":0},
      "legacy-1512":{"width":665.28,"lineCount":2,"horizontalNudge":8}
    }}
    """)
  // The current build edits one legacy entry and adds a new display; the untouched legacy
  // entry still migrates after the catalog is saved and reopened.
  catalog.set(CameraDockPreferences(width: 760, lineCount: 3), forDisplayUUID: "legacy-1728")
  catalog.set(CameraDockPreferences(width: 660, lineCount: 5), forDisplayUUID: "desk-1512")
  let restored = try JSONDecoder().decode(
    CameraDockPreferenceCatalog.self, from: JSONEncoder().encode(catalog))

  for subject in [catalog, restored] {
    #expect(
      subject.preference(forDisplayUUID: "legacy-1728", screenWidth: 1728)
        == CameraDockPreferences(width: 760, lineCount: 3))
    #expect(
      subject.preference(forDisplayUUID: "desk-1512", screenWidth: 1512)
        == CameraDockPreferences(width: 660, lineCount: 5))
    let migrated = subject.preference(forDisplayUUID: "legacy-1512", screenWidth: 1512)
    #expect(abs(migrated.width - 574.56) < 1e-9)
    #expect(migrated.lineCount == 2)
    #expect(migrated.horizontalNudge == 8)
  }
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

@Test func cameraDockDisplaySelectionFallsBackToTheSelectedMirroredBuiltIn() {
  let mirrored = CameraDockDisplayCandidate(id: "built-in", isBuiltIn: true, isMirrored: true)
  let external = CameraDockDisplayCandidate(id: "external", isBuiltIn: false, isMirrored: false)

  // A closed-lid mirror set whose only candidate is the built-in display still has a target.
  #expect(
    CameraDockDisplaySelection.preferred(in: [mirrored], selectedID: "built-in") == "built-in")
  #expect(
    CameraDockDisplaySelection.preferred(in: [external, mirrored], selectedID: "built-in")
      == "built-in")
  #expect(
    CameraDockDisplaySelection.preferred(in: [external, mirrored], selectedID: "external")
      == "external")
  // The selected mirrored built-in display has no usable hardware housing: the island is
  // emulated, and the opt-out tray stays detached.
  let parameters = CameraDockScreenParameters(
    screenFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1117),
    visibleFrame: CameraDockRect(x: 0, y: 0, width: 1728, height: 1080), safeTop: 32,
    auxiliaryTopLeftArea: CameraDockRect(x: 0, y: 1085, width: 700, height: 32),
    auxiliaryTopRightArea: CameraDockRect(x: 1028, y: 1085, width: 700, height: 32))
  let island = CameraDockGeometry.layout(
    on: parameters, isBuiltIn: true, isMirrored: true,
    preferences: CameraDockPreferences(width: 600), lineAdvance: 40)
  #expect(island?.style == .attached)
  #expect(island?.isEmulatedHousing == true)
  let tray = CameraDockGeometry.layout(
    on: parameters, isBuiltIn: true, isMirrored: true,
    preferences: CameraDockPreferences(width: 600, forceNotchAttachment: false), lineAdvance: 40)
  #expect(tray?.style == .detached)
}

@Test func attachedDockFitsWhenOnlyDetachedControlsWouldOverflow() throws {
  let screen = CameraDockRect(x: 0, y: 0, width: 1512, height: 200)
  let visible = CameraDockRect(x: 0, y: 0, width: 1512, height: 168)
  func placement(safeTop: Double, width: Double = 1512, attachedHeight: Double = 160)
    -> CameraDockPlacement?
  {
    CameraDockGeometry.placement(
      screenFrame: screen,
      visibleFrame: CameraDockRect(x: 0, y: 0, width: width, height: 168),
      safeTop: safeTop, auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil,
      isBuiltIn: true, width: 600, height: 204, attachedHeight: attachedHeight,
      horizontalNudge: 0)
  }
  let attached = try #require(placement(safeTop: 32))
  #expect(attached.location == .camera)
  #expect(attached.contentFrame.height == 160)
  #expect(attached.contentFrame.minY == 8)
  #expect(attached.contentFrame.isContained(in: visible))
  #expect(attached.frame.isContained(in: screen))
  #expect(placement(safeTop: 0) == nil)
  #expect(placement(safeTop: 32, attachedHeight: 169) == nil)
  #expect(placement(safeTop: 32, width: 359) == nil)
}
