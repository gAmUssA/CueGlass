import AppKit
import CueFlowCore

enum ImportError: LocalizedError {
  case unsupported, tooLarge, invalidRTF
  var errorDescription: String? {
    switch self {
    case .unsupported:
      "Choose a regular TXT, RTF, or CueGlass document (.cueflow). RTFD, PDF, and DOCX are unsupported."
    case .tooLarge: "This file exceeds the import limit. Split the script and try again."
    case .invalidRTF: "This file is not valid RTF. Export it as RTF or TXT and try again."
    }
  }
}
struct ImportResult {
  let attributed: NSAttributedString
  let warnings: [String]
}
@MainActor enum ScriptImporter {
  static func read(_ url: URL, encoding: String.Encoding? = nil) throws -> ImportResult {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else { throw ImportError.unsupported }
    let ext = url.pathExtension.lowercased()
    guard ["txt", "rtf"].contains(ext) else { throw ImportError.unsupported }
    let limit = (ext == "rtf" ? 16 : 8) * 1024 * 1024
    guard let size = values.fileSize, size <= limit else { throw ImportError.tooLarge }
    let data = try Data(contentsOf: url)
    guard data.count <= limit else { throw ImportError.tooLarge }
    if ext == "txt" {
      return ImportResult(
        attributed: NSAttributedString(
          string: try TextDecoding.decode(data, choice: encoding),
          attributes: [.font: NSFont.systemFont(ofSize: 18)]), warnings: [])
    }
    return try decodeRTF(data)
  }
  static func decodeRTF(_ data: Data) throws -> ImportResult {
    guard data.count <= 16 * 1024 * 1024, data.starts(with: Data("{\\rtf".utf8)) else {
      throw ImportError.invalidRTF
    }
    var attributes: NSDictionary?
    let text = try NSAttributedString(
      data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: &attributes)
    guard
      let type = attributes?[NSAttributedString.DocumentAttributeKey.documentType]
        as? NSAttributedString.DocumentType, type == .rtf
    else { throw ImportError.invalidRTF }
    var attachments = 0
    var tables = 0
    var links = 0
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, _, _ in
      if attrs[.attachment] != nil { attachments += 1 }
      if attrs[.link] != nil { links += 1 }
      if let p = attrs[.paragraphStyle] as? NSParagraphStyle,
        p.textBlocks.contains(where: { $0 is NSTextTableBlock })
      {
        tables += 1
      }
    }
    var warnings: [String] = []
    if attachments + tables > 0 {
      warnings.append(
        "\(attachments) attachments and \(tables) table runs are retained in source but simplified in presentation."
      )
    }
    if links > 0 {
      warnings.append("Links are retained in the editor and disabled in presentation.")
    }
    return ImportResult(attributed: text, warnings: warnings)
  }
  static func interactive(_ url: URL) throws -> ImportResult {
    do { return try read(url) } catch TextDecodingError.needsEncodingChoice {
      let panel = NSAlert()
      panel.messageText = "Choose the text encoding"
      panel.informativeText =
        "No characters will be silently replaced. Preview the chosen decoding before importing."
      let picker = NSPopUpButton(frame: NSRect(x: 0, y: 130, width: 400, height: 28))
      let choices: [(String, String.Encoding)] = [
        ("UTF-16 Little Endian", .utf16LittleEndian), ("UTF-16 Big Endian", .utf16BigEndian),
        ("Windows-1252", .windowsCP1252), ("Mac Roman", .macOSRoman),
        ("Windows-1251", .windowsCP1251),
      ]
      picker.addItems(withTitles: choices.map(\.0))
      panel.accessoryView = picker
      panel.addButton(withTitle: "Preview")
      panel.addButton(withTitle: "Cancel")
      guard panel.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
      let result = try read(url, encoding: choices[picker.indexOfSelectedItem].1)
      let preview = NSAlert()
      preview.messageText = "Import this decoding?"
      preview.informativeText = String(result.attributed.string.prefix(1200))
      preview.addButton(withTitle: "Import")
      preview.addButton(withTitle: "Cancel")
      guard preview.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
      return result
    }
  }
}
