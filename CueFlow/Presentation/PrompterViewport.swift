import AppKit
import CueFlowCore
import QuartzCore

@MainActor final class PassiveScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {}
}
@MainActor final class PrompterViewport: NSView {
  override var isFlipped: Bool { true }
  let scroll = PassiveScrollView()
  let text = NSTextView(usingTextLayoutManager: true)
  let guide = NSView()
  var driver: DisplayLinkDriver?
  private(set) var currentPosition: Double = 0
  private(set) var topPadding: Double = 0
  private var snapshotID: UUID?
  private var style = ReadingStyle()
  private var preparedUntil: Double = 0
  private(set) var endPosition: Double?
  var fractionalTranslation = true
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
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
    addSubview(scroll)
    guide.wantsLayer = true
    guide.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.6).cgColor
    addSubview(guide)
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
  func configure(snapshot: ScriptSnapshot, style: ReadingStyle, size: CGSize) {
    snapshotID = snapshot.id
    self.style = style
    frame.size = size
    topPadding = size.height * style.readingGuideFraction
    scroll.frame = bounds
    let width = max(80, size.width * style.columnWidthFraction - 40)
    let insetX = (size.width - width) / 2
    text.textContainerInset = CGSize(width: insetX, height: topPadding)
    text.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    text.textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    text.textStorage?.setAttributedString(
      PresentationBuilder.build(snapshot.attributed, style: style))
    layer?.backgroundColor = PresentationBuilder.color(style.backgroundRGBA).cgColor
    guide.frame = NSRect(x: 0, y: topPadding, width: size.width, height: 1)
    guide.isHidden = !style.showsReadingGuide
    preparedUntil = 0
    endPosition = nil
    prepareLayout(around: 0)
    apply(position: currentPosition)
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
      manager.enumerateTextLayoutFragments(from: nil, options: []) { fragment in
        if fragment.state == .layoutAvailable,
          content.offset(
            from: fragment.rangeInElement.endLocation, to: content.documentRange.endLocation) == 0
        {
          self.endPosition = max(0, fragment.layoutFragmentFrame.maxY)
        }
        return true
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
  var logicalSize = CGSize(width: 1280, height: 720) { didSet { needsLayout = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(reflection)
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
    reflection.setBoundsSize(logicalSize)
    reflection.needsLayout = true
  }
}
