import AppKit
import CueFlowCore

@MainActor enum PresentationBuilder {
  static func build(_ source: NSAttributedString, style: ReadingStyle) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: source)
    let range = NSRange(location: 0, length: result.length)
    result.removeAttribute(.link, range: range)
    result.removeAttribute(.attachment, range: range)
    source.enumerateAttributes(in: range) { attrs, run, _ in
      let original = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
      let size =
        style.mode == .normalized ? style.fontSize : original.pointSize * style.fontSize / 18
      var font =
        style.mode == .normalized
        ? PresentationFont.resolve(style)
        : NSFont(descriptor: original.fontDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
      let traits = NSFontManager.shared.traits(of: original).intersection([
        .boldFontMask, .italicFontMask,
      ])
      if style.mode == .normalized && traits.contains(.boldFontMask) {
        var emphasized = style
        emphasized.fontWeight = .bold
        font = PresentationFont.resolve(emphasized)
      }
      if traits.contains(.italicFontMask) {
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
      }
      if style.mode == .preserveSource {
        font = NSFontManager.shared.convert(font, toHaveTrait: traits)
      }
      let paragraph =
        (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        ?? NSMutableParagraphStyle()
      paragraph.textBlocks = []
      // Presentation line pitch is chosen independently of authored fixed heights.
      paragraph.minimumLineHeight = 0
      paragraph.maximumLineHeight = 0
      paragraph.lineHeightMultiple = style.lineHeightMultiplier
      paragraph.paragraphSpacing = style.paragraphSpacing
      result.addAttributes([.font: font, .paragraphStyle: paragraph], range: run)
      if style.mode == .normalized {
        result.addAttribute(.foregroundColor, value: color(style.foregroundRGBA), range: run)
      }
    }
    return result
  }
  static func color(_ values: [Double]) -> NSColor {
    NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: values[3])
  }
}
