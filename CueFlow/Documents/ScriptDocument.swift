import AppKit
import CueFlowCore
import os

@MainActor final class ScriptDocument: NSDocument {
  static let nativeType = "com.example.cueflow.script"
  static let replaced = Notification.Name("CueFlowDocumentReplaced")
  var source = NSAttributedString(
    string:
      "Welcome to CueFlow\n\nImport a TXT or RTF script, choose a display, then press Play.\n\nLEFT ← 1. Read at your own pace. → RIGHT\nUP ↑ 2. Adjust speed while playing. ↓ DOWN",
    attributes: [.font: NSFont.systemFont(ofSize: 18)])
  var model = ScriptDocumentModel(rtf: Data("{\\rtf1 }".utf8))
  private(set) var revision = 0
  private nonisolated let saveSafety = OSAllocatedUnfairLock<String?>(initialState: nil)
  nonisolated var saveBlockedReason: String? {
    get { saveSafety.withLock { $0 } }
    set { saveSafety.withLock { $0 = newValue } }
  }
  override func canAsynchronouslyWrite(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
  ) -> Bool { false }
  var notice = ""
  var cloudStatus: CloudStatus = .local
  override class var autosavesInPlace: Bool { true }
  override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
  override class var readableTypes: [String] { [nativeType, "public.plain-text", "public.rtf"] }
  override class var writableTypes: [String] { [nativeType] }
  override func makeWindowControllers() {
    addWindowController(OperatorWindowController(document: self))
  }
  func replaceSource(_ next: NSAttributedString, registerUndo: Bool = true) {
    let previous = source.copy() as! NSAttributedString
    if registerUndo {
      undoManager?.registerUndo(withTarget: self) { $0.replaceSource(previous) }
      undoManager?.setActionName("Edit Script")
    }
    source = next.copy() as! NSAttributedString
    revision += 1
    updateChangeCount(.changeDone)
    NotificationCenter.default.post(name: Self.replaced, object: self)
  }
  func setStyle(_ style: ReadingStyle) {
    let old = model.readingStyle
    undoManager?.registerUndo(withTarget: self) { $0.setStyle(old) }
    model.readingStyle = style
    updateChangeCount(.changeDone)
    NotificationCenter.default.post(name: Self.replaced, object: self)
  }
  override func data(ofType typeName: String) throws -> Data {
    var next = model
    next.content.data = try source.data(
      from: NSRange(location: 0, length: source.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    return try ScriptFileCodec.encode(next)
  }
  nonisolated override func read(from url: URL, ofType typeName: String) throws {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else { throw ImportError.unsupported }
    guard let bytes = values.fileSize, bytes <= ScriptFileCodec.maximumBytes else {
      throw ScriptFileError.tooLarge
    }
    try super.read(from: url, ofType: typeName)
  }
  nonisolated override func read(from data: Data, ofType typeName: String) throws {
    do {
      let decoded = try ScriptFileCodec.decode(data)
      try MainActor.assumeIsolated {
        let result = try ScriptImporter.decodeRTF(decoded.model.content.data)
        model = decoded.model
        source = result.attributed
        revision += 1
        saveBlockedReason = nil
        notice =
          (decoded.adjustedFields.isEmpty
          ? []
          : ["Adjusted out-of-range values: " + decoded.adjustedFields.joined(separator: ", ")])
          .joined() + result.warnings.joined(separator: " ")
        NotificationCenter.default.post(name: Self.replaced, object: self)
      }
    } catch let error as ScriptFileError {
      if case .futureVersion = error {
        MainActor.assumeIsolated {
          saveBlockedReason =
            "A newer document version is on disk. Save a Copy or update CueFlow before saving."
        }
      }
      throw error
    }
  }
  override func checkAutosavingSafety() throws {
    if let reason = saveBlockedReason {
      throw NSError(domain: "CueFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
    try super.checkAutosavingSafety()
  }
  override func writeSafely(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
  ) throws {
    if let reason = saveBlockedReason, saveOperation != .saveToOperation {
      throw NSError(domain: "CueFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
    try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
  }
  nonisolated override var observedPresentedItemUbiquityAttributes: Set<URLResourceKey> {
    CloudMetadata.keys
  }
  nonisolated override func presentedItemDidChangeUbiquityAttributes(
    _ attributes: Set<URLResourceKey>
  ) {
    super.presentedItemDidChangeUbiquityAttributes(attributes)
    Task { @MainActor [weak self] in await self?.refreshCloudStatus() }
  }
  func refreshCloudStatus() async {
    guard let fileURL else {
      cloudStatus = .local
      return
    }
    do {
      cloudStatus = CloudStatus.map(try await DocumentStorageService.shared.metadata(fileURL))
    } catch let error as NSError {
      cloudStatus = .error
      notice = "Could not read iCloud status (\(error.code)). Use Save a Copy to keep local work."
    }
    NotificationCenter.default.post(name: Self.replaced, object: self)
  }
}

@MainActor final class CueFlowDocumentController: NSDocumentController {
  override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument
  {
    if ["txt", "rtf"].contains(url.pathExtension.lowercased()) {
      let result = try ScriptImporter.interactive(url)
      if !result.warnings.isEmpty {
        let alert = NSAlert()
        alert.messageText = "Presentation simplification"
        alert.informativeText = result.warnings.joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
      }
      let doc = ScriptDocument()
      doc.source = result.attributed
      doc.model.title = url.deletingPathExtension().lastPathComponent
      doc.notice = result.warnings.joined(separator: " ")
      doc.fileType = ScriptDocument.nativeType
      doc.updateChangeCount(.changeDone)
      return doc
    }
    let values = try url.resourceValues(forKeys: [
      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ])
    if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
      Task {
        do { try await DocumentStorageService.shared.download(url) } catch let error as NSError {
          NSApp.presentError(error)
        }
      }
      throw NSError(
        domain: "CueFlow", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "This script is downloading from iCloud. Open it again when the download finishes. Local scripts remain available offline."
        ])
    }
    return try super.makeDocument(withContentsOf: url, ofType: typeName)
  }
}
