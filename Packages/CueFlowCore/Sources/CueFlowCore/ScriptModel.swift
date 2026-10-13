import Foundation

public struct ReadingStyle: Codable, Sendable, Equatable {
  public enum Mode: String, Codable, Sendable { case normalized, preserveSource }
  public var mode: Mode = .normalized
  public var fontIdentifier: String? = nil
  public var fontSize: Double = 64
  public var lineHeightMultiplier: Double = 1.3
  public var paragraphSpacing: Double = 16
  public var columnWidthFraction: Double = 0.7
  public var foregroundRGBA: [Double] = [1, 1, 1, 1]
  public var backgroundRGBA: [Double] = [0.025, 0.025, 0.025, 1]
  public var readingGuideFraction: Double = 0.35
  public var showsReadingGuide = true
  public init() {}
}
public struct ScriptDocumentModel: Codable, Sendable, Equatable {
  public struct Content: Codable, Sendable, Equatable {
    public var format = "rtf"
    public var data: Data
    public init(data: Data) { self.data = data }
  }
  public var formatVersion = 1
  public var documentID: UUID
  public var title: String
  public var content: Content
  public var readingStyle = ReadingStyle()
  public var preferredSpeedPointsPerSecond: Double = 40
  public init(documentID: UUID = UUID(), title: String = "Untitled", rtf: Data) {
    self.documentID = documentID
    self.title = title
    content = Content(data: rtf)
  }
}
public enum ScriptFileError: Error, Equatable {
  case tooLarge, malformed
  case futureVersion(Int)
  case invalidVersion, invalidPayload
  case invalidNumber(String)
}
public struct DecodedScript: Sendable {
  public var model: ScriptDocumentModel
  public var adjustedFields: [String]
}
public enum ScriptFileCodec {
  public static let maximumBytes = 32 * 1024 * 1024
  public static func decode(_ data: Data) throws -> DecodedScript {
    guard data.count <= maximumBytes else { throw ScriptFileError.tooLarge }
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let number = object["formatVersion"] as? NSNumber, String(cString: number.objCType) != "c",
      let version = object["formatVersion"] as? Int
    else { throw ScriptFileError.malformed }
    guard version <= 1 else { throw ScriptFileError.futureVersion(version) }
    guard version == 1 else { throw ScriptFileError.invalidVersion }
    // Explicit defaults for optional style/speed/title fields; required identity/content remain required.
    let defaults =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(ReadingStyle())) as? [String: Any]
      ?? [:]
    var style = object["readingStyle"] as? [String: Any] ?? [:]
    for (key, value) in defaults where style[key] == nil { style[key] = value }
    object["readingStyle"] = style
    if object["preferredSpeedPointsPerSecond"] == nil {
      object["preferredSpeedPointsPerSecond"] = 40
    }
    if object["title"] == nil { object["title"] = "Untitled" }
    var model = try JSONDecoder().decode(
      ScriptDocumentModel.self, from: JSONSerialization.data(withJSONObject: object))
    let adjusted = try validate(&model)
    return DecodedScript(model: model, adjustedFields: adjusted)
  }
  public static func encode(_ model: ScriptDocumentModel) throws -> Data {
    var checked = model
    _ = try validate(&checked)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try encoder.encode(checked)
    guard data.count <= maximumBytes else { throw ScriptFileError.tooLarge }
    return data
  }
  public static func validatedStyle(_ style: ReadingStyle) throws -> ReadingStyle {
    var model = ScriptDocumentModel(rtf: Data("{\\rtf1 }".utf8))
    model.readingStyle = style
    _ = try validate(&model)
    return model.readingStyle
  }
  private static func validate(_ model: inout ScriptDocumentModel) throws -> [String] {
    guard model.formatVersion == 1 else { throw ScriptFileError.invalidVersion }
    guard model.content.format == "rtf", model.content.data.count <= 16 * 1024 * 1024,
      model.content.data.starts(with: Data("{\\rtf".utf8))
    else { throw ScriptFileError.invalidPayload }
    var adjusted: [String] = []
    func clamp(_ value: inout Double, _ range: ClosedRange<Double>, _ field: String) throws {
      guard value.isFinite else { throw ScriptFileError.invalidNumber(field) }
      let next = min(range.upperBound, max(range.lowerBound, value))
      if next != value {
        adjusted.append(field)
        value = next
      }
    }
    try clamp(&model.preferredSpeedPointsPerSecond, 1...300, "speed")
    try clamp(&model.readingStyle.fontSize, 18...180, "font size")
    try clamp(&model.readingStyle.lineHeightMultiplier, 1...2, "line height")
    try clamp(&model.readingStyle.paragraphSpacing, 0...200, "paragraph spacing")
    try clamp(&model.readingStyle.columnWidthFraction, 0.25...1, "column width")
    try clamp(&model.readingStyle.readingGuideFraction, 0...1, "guide")
    for key in ["foreground", "background"] {
      var values =
        key == "foreground" ? model.readingStyle.foregroundRGBA : model.readingStyle.backgroundRGBA
      guard values.count == 4 else { throw ScriptFileError.invalidNumber(key) }
      for i in values.indices { try clamp(&values[i], 0...1, key) }
      if key == "foreground" {
        model.readingStyle.foregroundRGBA = values
      } else {
        model.readingStyle.backgroundRGBA = values
      }
    }
    guard (model.readingStyle.fontIdentifier?.count ?? 0) <= 256 else {
      throw ScriptFileError.malformed
    }
    model.title = String(model.title.unicodeScalars.filter { $0.value >= 32 }.prefix(512))
    return adjusted
  }
}

extension ScriptFileError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .tooLarge: "The CueFlow document exceeds 32 MiB. Split the script before importing."
    case .futureVersion(let version):
      "This file uses CueFlow format \(version). Update CueFlow or save the current work as a copy. The newer file will not be overwritten."
    case .invalidVersion, .malformed:
      "The CueFlow document is invalid. Choose a valid script; the previous document is kept."
    case .invalidPayload:
      "The script does not contain a supported RTF payload. Export a TXT or RTF copy and import it."
    case .invalidNumber(let field):
      "The document has an invalid \(field) value. Correct the file or import its text into a new script."
    }
  }
}
