import AppKit
import CueFlowCore

@MainActor enum PresentationFont {
  static func resolve(_ style: ReadingStyle) -> NSFont {
    let weights: [ReadingStyle.Weight: NSFont.Weight] = [
      .regular: .regular, .medium: .medium, .semibold: .semibold, .bold: .bold,
    ]
    if let name = style.fontIdentifier, let font = NSFont(name: name, size: style.fontSize) {
      let descriptor = font.fontDescriptor.addingAttributes([
        .traits: [NSFontDescriptor.TraitKey.weight: (weights[style.fontWeight] ?? .medium).rawValue]
      ])
      return NSFont(descriptor: descriptor, size: style.fontSize) ?? font
    }
    let font = NSFont.systemFont(
      ofSize: style.fontSize, weight: weights[style.fontWeight] ?? .medium)
    if style.fontIdentifier == nil, style.systemDesign == .serif,
      let descriptor = font.fontDescriptor.withDesign(.serif)
    {
      return NSFont(descriptor: descriptor, size: style.fontSize) ?? font
    }
    return font
  }
  static func lineAdvance(_ style: ReadingStyle) -> Double {
    let font = resolve(style)
    return (font.ascender - font.descender + font.leading) * style.lineHeightMultiplier
  }
  static func notice(_ style: ReadingStyle) -> String? {
    guard let name = style.fontIdentifier, NSFont(name: name, size: style.fontSize) == nil else {
      return nil
    }
    return
      "Font unavailable — using the system font. Install the saved family or choose another font."
  }
}
