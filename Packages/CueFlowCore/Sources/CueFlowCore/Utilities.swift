import Foundation

public enum TextDecodingError: Error { case needsEncodingChoice, tooLarge }
public enum TextDecoding {
  public static func decode(_ data: Data, choice: String.Encoding? = nil) throws -> String {
    guard data.count <= 8 * 1024 * 1024 else { throw TextDecodingError.tooLarge }
    let text: String?
    if let choice {
      text = String(data: data, encoding: choice)
    } else if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      text = String(data: data.dropFirst(3), encoding: .utf8)
    } else if data.starts(with: [0xFF, 0xFE]) {
      text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
    } else if data.starts(with: [0xFE, 0xFF]) {
      text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
    } else {
      text = String(data: data, encoding: .utf8)
    }
    guard let text else { throw TextDecodingError.needsEncodingChoice }
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")
  }
}
public enum GraphemeBoundary {
  public static func alignDown(_ offset: Int, in text: String) -> Int {
    let clamped = min(text.utf16.count, max(0, offset))
    var result = 0
    var cursor = 0
    for character in text {
      cursor += String(character).utf16.count
      if cursor > clamped { break }
      result = cursor
    }
    return result
  }
}
public struct ReadingAnchor: Sendable, Equatable {
  public var snapshotID: UUID
  public var utf16Offset: Int
  public var intraLineFraction: Double
  public init(snapshotID: UUID, utf16Offset: Int, intraLineFraction: Double = 0) {
    self.snapshotID = snapshotID
    self.utf16Offset = utf16Offset
    self.intraLineFraction = intraLineFraction
  }
  public func isValid(for id: UUID, text: String) -> Bool {
    snapshotID == id && utf16Offset >= 0 && utf16Offset <= text.utf16.count
      && intraLineFraction.isFinite && (0...1).contains(intraLineFraction)
      && GraphemeBoundary.alignDown(utf16Offset, in: text) == utf16Offset
  }
}
public enum AnchorCarryOver {
  public static func offset(old: String, new: String, offset: Int) -> Int {
    old == new ? GraphemeBoundary.alignDown(offset, in: new) : 0
  }
}
public struct Affine2D: Sendable, Equatable {
  public var sx: Double
  public var sy: Double
  public var tx: Double
  public var ty: Double
  public static func reflection(width: Double, height: Double, horizontal: Bool, vertical: Bool)
    -> Self
  {
    Self(
      sx: horizontal ? -1 : 1, sy: vertical ? -1 : 1, tx: horizontal ? width : 0,
      ty: vertical ? height : 0)
  }
  public func map(x: Double, y: Double) -> (Double, Double) { (sx * x + tx, sy * y + ty) }
}
public struct DisplayPreference: Codable, Sendable, Equatable {
  public var uuid: String?
  public var name: String
  public init(uuid: String?, name: String) {
    self.uuid = uuid
    self.name = name
  }
}
public enum DisplayMatcher {
  public static func match(_ saved: DisplayPreference, in displays: [DisplayPreference]) -> Int? {
    if let uuid = saved.uuid, let index = displays.firstIndex(where: { $0.uuid == uuid }) {
      return index
    }
    let indices = displays.indices.filter { displays[$0].name == saved.name }
    return indices.count == 1 ? indices[0] : nil
  }
}
public struct CloudResourceSnapshot: Sendable {
  public var ubiquitous: Bool
  public var downloaded: Bool
  public var downloading: Bool
  public var uploading: Bool
  public var uploaded: Bool
  public var conflict: Bool
  public var error: Bool
  public init(
    ubiquitous: Bool = false, downloaded: Bool = true, downloading: Bool = false,
    uploading: Bool = false, uploaded: Bool = false, conflict: Bool = false, error: Bool = false
  ) {
    self.ubiquitous = ubiquitous
    self.downloaded = downloaded
    self.downloading = downloading
    self.uploading = uploading
    self.uploaded = uploaded
    self.conflict = conflict
    self.error = error
  }
}
public enum CloudStatus: String, Sendable {
  case local = "On This Mac"
  case notDownloaded = "Not downloaded — request download"
  case downloading = "Downloading…"
  case uploading = "Uploading…"
  case uploadedToICloud = "Uploaded to iCloud"
  case conflict = "Conflict — browse versions or save a copy"
  case error = "iCloud error — save a local copy"
  case unknown = "iCloud status unknown"
  public static func map(_ s: CloudResourceSnapshot) -> Self {
    if s.error { return .error }
    if s.conflict { return .conflict }
    if !s.ubiquitous { return .local }
    if s.downloading { return .downloading }
    if !s.downloaded { return .notDownloaded }
    if s.uploading { return .uploading }
    if s.uploaded { return .uploadedToICloud }
    return .unknown
  }
}
