import CueFlowCore
import Foundation

actor DocumentStorageService {
  static let shared = DocumentStorageService()
  func container(identifier: String) throws -> URL? {
    guard !identifier.isEmpty, FileManager.default.ubiquityIdentityToken != nil else { return nil }
    guard let root = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else {
      return nil
    }
    let documents = root.appendingPathComponent("Documents", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    return documents
  }
  func metadata(_ url: URL) throws -> CloudResourceSnapshot { try CloudMetadata.read(url) }
  func download(_ url: URL) throws {
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
  }
}
enum CloudMetadata {
  static let keys: Set<URLResourceKey> = [
    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
    .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
    .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemDownloadingErrorKey,
    .ubiquitousItemUploadingErrorKey,
  ]
  static func read(_ url: URL) throws -> CloudResourceSnapshot {
    let v = try url.resourceValues(forKeys: keys)
    return .init(
      ubiquitous: v.isUbiquitousItem == true,
      downloaded: v.ubiquitousItemDownloadingStatus != .notDownloaded,
      downloading: v.ubiquitousItemIsDownloading == true,
      uploading: v.ubiquitousItemIsUploading == true, uploaded: v.ubiquitousItemIsUploaded == true,
      conflict: v.ubiquitousItemHasUnresolvedConflicts == true,
      error: v.ubiquitousItemDownloadingError != nil || v.ubiquitousItemUploadingError != nil)
  }
}
