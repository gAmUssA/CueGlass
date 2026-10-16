import AppKit
import CueFlowCore
import QuartzCore

@MainActor final class PassiveScrollView: NSScrollView {
  var onScrub: ((NSEvent) -> Void)?
  override func scrollWheel(with event: NSEvent) { onScrub?(event) }
}
@MainActor final class PrompterViewport: NSView {
  override var isFlipped: Bool { true }
  let scroll = PassiveScrollView()
  let text = NSTextView(usingTextLayoutManager: true)
  let guide = ReadingGuideView()
  let panelBackground = NSView()
  let countdown = NSTextField(labelWithString: "")
  private var measurementGeneration = 0
  private var fadesTopEdge = true
  private(set) var layoutCount = 0
  private(set) var measurementChunkCount = 0
  private(set) var measurementWorstSeconds = 0.0
  private(set) var measurementTotalSeconds = 0.0
  var onScrub: ((NSEvent) -> Void)? { didSet { scroll.onScrub = onScrub } }
  var driver: DisplayLinkDriver?
  private(set) var currentPosition: Double = 0
  private(set) var topPadding: Double = 0
  private var snapshotID: UUID?
  private var style = ReadingStyle()
  private var preparedUntil: Double = 0
  private(set) var endPosition: Double?
  private(set) var voiceLineTable: VoiceLineTable?
  var fractionalTranslation = true
  var compactCountdown = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    scroll.wantsLayer = true
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    scroll.verticalScrollElasticity = .none
    scroll.horizontalScrollElasticity = .none
    text.isEditable = false
    text.isSelectable = false
    text.drawsBackground = false
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.wantsLayer = true
    text.textContainer?.widthTracksTextView = true
    text.textContainer?.heightTracksTextView = false
    scroll.documentView = text
    panelBackground.wantsLayer = true
    addSubview(panelBackground)
    addSubview(scroll)
    guide.wantsLayer = true
    guide.layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(guide)
    countdown.alignment = .center
    countdown.font = .monospacedDigitSystemFont(ofSize: 96, weight: .semibold)
    countdown.textColor = .white
    countdown.isHidden = true
    addSubview(countdown)
    #if DEBUG
      NotificationCenter.default.addObserver(
        self, selector: #selector(legacyFallback),
        name: NSTextView.willSwitchToNSLayoutManagerNotification, object: text)
    #endif
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
  @objc private func legacyFallback() {
    assertionFailure("Presentation switched away from TextKit 2")
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { driver?.stop() }
    super.viewWillMove(toWindow: newWindow)
  }
  func configure(
    snapshot: ScriptSnapshot, style: ReadingStyle, size: CGSize,
    guideFractionOverride: Double? = nil, fadesTopEdge: Bool = true
  ) {
    measurementGeneration += 1
    layoutCount += 1
    snapshotID = snapshot.id
    voiceLineTable = nil
    self.style = style
    self.fadesTopEdge = fadesTopEdge
    frame.size = size
    topPadding = size.height * (guideFractionOverride ?? style.readingGuideFraction)
    scroll.frame = bounds
    let width = max(80, size.width * style.columnWidthFraction * (1 - 2 * style.sideMarginFraction))
    let insetX = (size.width - width) / 2
    text.textContainerInset = CGSize(width: insetX, height: topPadding)
    text.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    text.textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    text.textStorage?.setAttributedString(
      PresentationBuilder.build(snapshot.attributed, style: style))
    updateAids(style)
    preparedUntil = 0
    endPosition = nil
    prepareLayout(around: 0)
    apply(position: currentPosition)
  }
  func showCountdown(_ digit: Int?) {
    if digit == nil && countdown.isHidden { return }
    countdown.isHidden = digit == nil
    if let digit, countdown.stringValue != String(digit) { countdown.stringValue = String(digit) }
    if compactCountdown {
      countdown.font = .monospacedDigitSystemFont(
        ofSize: min(96, max(28, bounds.height * 0.45)), weight: .semibold)
    }
    countdown.frame = CGRect(x: 0, y: bounds.height * 0.25, width: bounds.width, height: 120)
  }
  func updateAids(_ next: ReadingStyle) {
    let previous = style
    if previous.foregroundRGBA != next.foregroundRGBA && next.mode == .normalized {
      text.textStorage?.addAttribute(
        .foregroundColor, value: PresentationBuilder.color(next.foregroundRGBA),
        range: NSRange(location: 0, length: text.string.utf16.count))
    }
    style = next
    layer?.backgroundColor = NSColor.clear.cgColor
    let width = bounds.width * next.columnWidthFraction
    panelBackground.frame = CGRect(
      x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    panelBackground.layer?.backgroundColor =
      PresentationBuilder.color(next.backgroundRGBA).withAlphaComponent(next.textPanelOpacity)
      .cgColor
    guide.frame = NSRect(x: 0, y: topPadding - 8, width: bounds.width, height: 16)
    guide.style = next
    guide.needsDisplay = true
    guide.isHidden = !next.showsReadingGuide
    if next.edgeFadeFraction > 0 {
      let mask = CAGradientLayer()
      mask.frame = bounds
      mask.isGeometryFlipped = scroll.layer?.isGeometryFlipped ?? scroll.isFlipped
      mask.startPoint = CGPoint(x: 0.5, y: mask.isGeometryFlipped ? 1 : 0)
      mask.endPoint = CGPoint(x: 0.5, y: mask.isGeometryFlipped ? 0 : 1)
      mask.colors =
        fadesTopEdge
        ? [
          NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor,
          NSColor.clear.cgColor,
        ]
        : [
          NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor,
          NSColor.black.cgColor,
        ]
      mask.locations = [
        0, NSNumber(value: next.edgeFadeFraction), NSNumber(value: 1 - next.edgeFadeFraction), 1,
      ]
      scroll.layer?.mask = mask
    } else {
      scroll.layer?.mask = nil
    }
  }
  /// Bounded work per main-run-loop turn; never called by the display callback.
  func measure(completion: @escaping (Double, [Double], Int, Int) -> Void) {
    guard let manager = text.textLayoutManager, let content = manager.textContentManager else {
      return
    }
    let generation = measurementGeneration
    let measurementStart = CACurrentMediaTime()
    let sourceLength = text.string.utf16.count
    measurementChunkCount = 0
    measurementWorstSeconds = 0
    let offsets = Set(ParagraphIndex.starts(in: text.string))
    let wordCount = text.string.split(whereSeparator: { $0.isWhitespace }).count
    var positions: [Double] = []
    var voiceLines: [VoiceLine] = []
    var lines = 0
    var end = 0.0
    var cursor: NSTextLocation? = content.documentRange.location
    func chunk() {
      guard generation == self.measurementGeneration else { return }
      let chunkStart = CACurrentMediaTime()
      self.measurementChunkCount += 1
      var visited = 0
      var finished = false
      manager.enumerateTextLayoutFragments(from: cursor, options: [.ensuresLayout]) { fragment in
        let start = content.offset(
          from: content.documentRange.location, to: fragment.rangeInElement.location)
        if offsets.contains(start) { positions.append(fragment.layoutFragmentFrame.minY) }
        lines += fragment.textLineFragments.count
        for line in fragment.textLineFragments {
          let lower = start + line.characterRange.location
          let upper = min(sourceLength, lower + line.characterRange.length)
          guard lower >= 0, lower < upper else { continue }
          voiceLines.append(
            VoiceLine(
              utf16Range: lower..<upper,
              minY: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY))
        }
        end = max(end, fragment.layoutFragmentFrame.maxY)
        cursor = fragment.rangeInElement.endLocation
        visited += 1
        if content.offset(
          from: fragment.rangeInElement.endLocation, to: content.documentRange.endLocation) == 0
        {
          finished = true
          return false
        }
        return visited < 64
      }
      self.measurementWorstSeconds = max(
        self.measurementWorstSeconds, CACurrentMediaTime() - chunkStart)
      if finished || visited == 0 {
        self.measurementTotalSeconds = CACurrentMediaTime() - measurementStart
        self.endPosition = end
        self.voiceLineTable = VoiceLineTable(lines: voiceLines)
        self.text.frame.size.height = max(
          self.bounds.height, end + self.bounds.height + self.topPadding)
        completion(end, positions, wordCount, lines)
      } else {
        DispatchQueue.main.async { chunk() }
      }
    }
    chunk()
  }
  private func prepareLayout(around position: Double) {
    guard let manager = text.textLayoutManager, let content = manager.textContentManager else {
      return
    }
    if position + bounds.height >= preparedUntil {
      let rect = CGRect(
        x: 0, y: max(0, position - topPadding), width: bounds.width, height: bounds.height * 3)
      manager.ensureLayout(for: rect)
      preparedUntil = position + bounds.height * 2
      // The final fragment must actually be laid out, not an estimated usage bound.
      if endPosition == nil {
        let nearby = manager.textLayoutFragment(for: CGPoint(x: 0, y: position))?.rangeInElement
          .location
        manager.enumerateTextLayoutFragments(from: nearby, options: []) { fragment in
          if fragment.state == .layoutAvailable,
            content.offset(
              from: fragment.rangeInElement.endLocation, to: content.documentRange.endLocation) == 0
          {
            self.endPosition = max(0, fragment.layoutFragmentFrame.maxY)
          }
          return fragment.state == .layoutAvailable
            && fragment.layoutFragmentFrame.minY < position + self.bounds.height * 3
        }
      }
    }
    let ensuredHeight = max(bounds.height, preparedUntil + bounds.height + topPadding)
    let height = max(ensuredHeight, (endPosition ?? 0) + bounds.height)
    if text.frame.height != height { text.frame.size.height = height }
  }
  func apply(position: Double) {
    currentPosition = max(0, position)
    prepareLayout(around: currentPosition)
    let scale = window?.backingScaleFactor ?? 1
    let aligned = floor(currentPosition * scale) / scale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: aligned))
    scroll.reflectScrolledClipView(scroll.contentView)
    text.layer?.transform = CATransform3DMakeTranslation(
      0, fractionalTranslation ? -(currentPosition - aligned) : 0, 0)
    CATransaction.commit()
  }
  func captureAnchor() -> ReadingAnchor? {
    guard let id = snapshotID, let manager = text.textLayoutManager,
      let content = manager.textContentManager
    else { return nil }
    let y = currentPosition  // TextKit fragment coordinates exclude the text-container inset.
    guard let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else {
      return ReadingAnchor(snapshotID: id, utf16Offset: 0)
    }
    let line =
      fragment.textLineFragments.first(where: {
        fragment.layoutFragmentFrame.minY + $0.typographicBounds.maxY >= y
      }) ?? fragment.textLineFragments.last
    guard let line else { return ReadingAnchor(snapshotID: id, utf16Offset: 0) }
    let start =
      content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
      + line.characterRange.location
    let offset = GraphemeBoundary.alignDown(start, in: text.string)
    let fraction = min(
      1,
      max(
        0,
        (y - fragment.layoutFragmentFrame.minY - line.typographicBounds.minY)
          / max(1, line.typographicBounds.height)))
    return ReadingAnchor(snapshotID: id, utf16Offset: offset, intraLineFraction: fraction)
  }
  func restore(_ anchor: ReadingAnchor) -> Double? {
    guard let id = snapshotID, anchor.isValid(for: id, text: text.string),
      let manager = text.textLayoutManager, let content = manager.textContentManager,
      let location = content.location(content.documentRange.location, offsetBy: anchor.utf16Offset),
      let range = NSTextRange(location: content.documentRange.location, end: location)
    else { return nil }
    manager.ensureLayout(for: range)
    guard let fragment = manager.textLayoutFragment(for: location) else { return nil }
    let relative = content.offset(from: fragment.rangeInElement.location, to: location)
    let line =
      fragment.textLineFragments.first { NSLocationInRange(relative, $0.characterRange) }
      ?? fragment.textLineFragments.last
    guard let line else { return nil }
    return max(
      0,
      fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.typographicBounds
        .height * anchor.intraLineFraction)
  }
}
@MainActor final class ReflectionContainerView: NSView {
  let viewport = PrompterViewport(frame: .zero)
  var horizontal = false { didSet { needsLayout = true } }
  var vertical = false { didSet { needsLayout = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    addSubview(viewport)
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
  override func layout() {
    super.layout()
    viewport.frame = bounds
    let a = Affine2D.reflection(
      width: bounds.width, height: bounds.height, horizontal: horizontal, vertical: vertical)
    var transform = CATransform3DIdentity
    transform.m11 = a.sx
    transform.m22 = a.sy
    transform.m41 = a.tx
    transform.m42 = a.ty
    layer?.sublayerTransform = transform
  }
}
@MainActor final class ScaledPreviewContainer: NSView {
  let reflection = ReflectionContainerView(frame: .zero)
  let placementMapView = CameraDockPlacementMapView(frame: .zero)
  var logicalSize = CGSize(width: 1280, height: 720) {
    didSet {
      reflection.bounds = CGRect(origin: .zero, size: logicalSize)
      reflection.layoutSubtreeIfNeeded()
      needsLayout = true
    }
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(reflection)
    placementMapView.isHidden = true
    addSubview(placementMapView)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
  }
  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
  override func layout() {
    super.layout()
    let scale = min(bounds.width / logicalSize.width, bounds.height / logicalSize.height)
    let size = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
    reflection.frame = CGRect(
      x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width,
      height: size.height)
    placementMapView.frame = bounds
    placementMapView.needsDisplay = true
    reflection.bounds = CGRect(origin: .zero, size: logicalSize)
    reflection.needsLayout = true
    reflection.layoutSubtreeIfNeeded()
    // Native clip views may reset their origin while their ancestor is scaled.
    reflection.viewport.apply(position: reflection.viewport.currentPosition)
  }
}

@MainActor final class CameraDockPlacementMapView: NSView {
  var map: CameraDockPlacementMap? { didSet { needsDisplay = true } }

  override var isOpaque: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    NSColor(srgbRed: 0.055, green: 0.059, blue: 0.067, alpha: 1).setFill()
    bounds.fill()
    guard let map else { return }

    let available = bounds.insetBy(dx: 8, dy: 8)
    let aspect = map.displayAspectRatio
    let width = min(available.width, available.height * aspect)
    let height = width / aspect
    let display = CGRect(
      x: available.midX - width / 2, y: available.midY - height / 2,
      width: width, height: height)
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(rect: display).fill()
    NSColor(srgbRed: 0.38, green: 0.4, blue: 0.44, alpha: 1).setStroke()
    NSBezierPath(rect: display).stroke()

    func screenRect(_ rect: CameraDockRect) -> CGRect {
      CGRect(
        x: display.minX + display.width * rect.x,
        y: display.minY + display.height * rect.y,
        width: display.width * rect.width,
        height: display.height * rect.height)
    }

    NSColor(srgbRed: 0.09, green: 0.1, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(rect: screenRect(map.menuBarBand)).fill()
    if let housing = map.cameraHousing {
      let rect = screenRect(housing)
      let radius = min(5, rect.height / 3)
      let path = NSBezierPath()
      path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
      path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
      path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
      path.curve(
        to: NSPoint(x: rect.maxX - radius, y: rect.minY),
        controlPoint1: NSPoint(x: rect.maxX, y: rect.minY),
        controlPoint2: NSPoint(x: rect.maxX - radius, y: rect.minY))
      path.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
      path.curve(
        to: NSPoint(x: rect.minX, y: rect.minY + radius),
        controlPoint1: NSPoint(x: rect.minX + radius, y: rect.minY),
        controlPoint2: NSPoint(x: rect.minX, y: rect.minY))
      path.close()
      NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).setFill()
      path.fill()
    }

    let dockRect = screenRect(map.dock)
    switch map.style {
    case .attached: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).setFill()
    case .detached: NSColor(srgbRed: 0.039, green: 0.039, blue: 0.043, alpha: 1).setFill()
    }
    NSBezierPath(rect: dockRect).fill()
    NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
    let outline = NSBezierPath(rect: dockRect)
    outline.lineWidth = 1
    outline.stroke()
    let contentRect = screenRect(map.content)
    NSColor.white.withAlphaComponent(0.75).setStroke()
    let contentOutline = NSBezierPath(roundedRect: contentRect, xRadius: 3, yRadius: 3)
    contentOutline.lineWidth = 0.75
    contentOutline.stroke()
  }
}

@MainActor final class ReadingGuideView: NSView {
  var style = ReadingStyle()
  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.withAlphaComponent(
      NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        ? max(0.5, style.readingGuideOpacity) : style.readingGuideOpacity
    ).setFill()
    if style.readingGuideStyle != .triangle {
      NSRect(x: 20, y: 7.5, width: max(0, bounds.width - 40), height: 1).fill()
    }
    if style.readingGuideStyle != .line {
      for right in [false, true] {
        let path = NSBezierPath()
        let x = right ? bounds.width - 4 : 4
        let sign: CGFloat = right ? -1 : 1
        path.move(to: NSPoint(x: x, y: 0))
        path.line(to: NSPoint(x: x + sign * 12, y: 8))
        path.line(to: NSPoint(x: x, y: 16))
        path.close()
        path.fill()
      }
    }
  }
}
