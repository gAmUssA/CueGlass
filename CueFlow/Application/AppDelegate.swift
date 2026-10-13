import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var documents: CueFlowDocumentController?
  func applicationWillFinishLaunching(_ notification: Notification) {
    documents = CueFlowDocumentController()
    buildMenu()
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.environment["CUEFLOW_EPHEMERAL"] == "1"
    {
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    if NSDocumentController.shared.documents.isEmpty {
      NSDocumentController.shared.newDocument(nil)
    }
  }
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
  func buildMenu() {
    let main = NSMenu()
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      item.title = title
      let submenu = NSMenu(title: title)
      item.submenu = submenu
      main.addItem(item)
      return submenu
    }
    func add(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      modifiers: NSEvent.ModifierFlags = .command
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      menu.addItem(item)
    }
    let app = menu("CueFlow")
    add(app, "About CueFlow", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    app.addItem(.separator())
    add(app, "Hide CueFlow", #selector(NSApplication.hide(_:)), "h")
    add(app, "Quit CueFlow", #selector(NSApplication.terminate(_:)), "q")
    let file = menu("File")
    add(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
    add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
    let recentsItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    let recents = NSMenu(title: "Open Recent")
    recents.identifier = NSUserInterfaceItemIdentifier("CueFlowRecents")
    recents.delegate = self
    recentsItem.submenu = recents
    file.addItem(recentsItem)
    add(recents, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
    add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    add(file, "Save…", #selector(NSDocument.save(_:)), "s")
    add(
      file, "Save a Copy…", #selector(NSDocument.saveTo(_:)), "s", modifiers: [.command, .option])
    add(file, "Move To…", #selector(NSDocument.move(_:)))
    add(file, "Browse Versions…", #selector(NSDocument.browseVersions(_:)))
    let edit = menu("Edit")
    add(edit, "Undo", Selector(("undo:")), "z")
    add(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
    edit.addItem(.separator())
    add(edit, "Cut", #selector(NSText.cut(_:)), "x")
    add(edit, "Copy", #selector(NSText.copy(_:)), "c")
    add(edit, "Paste", #selector(NSText.paste(_:)), "v")
    add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
    let format = menu("Format")
    add(format, "Bold", #selector(NSFontManager.addFontTrait(_:)), "b")
    format.items.last?.tag = Int(NSFontTraitMask.boldFontMask.rawValue)
    add(format, "Italic", #selector(NSFontManager.addFontTrait(_:)), "i")
    format.items.last?.tag = Int(NSFontTraitMask.italicFontMask.rawValue)
    add(format, "Show Fonts", #selector(NSFontManager.orderFrontFontPanel(_:)), "t")
    for item in format.items { item.target = NSFontManager.shared }
    let playback = menu("Playback")
    add(playback, "Play / Pause", #selector(toggle), "p", modifiers: [.command, .option])
    add(
      playback, "Faster", #selector(faster), String(UnicodeScalar(NSUpArrowFunctionKey)!),
      modifiers: [.command, .option])
    add(
      playback, "Slower", #selector(slower), String(UnicodeScalar(NSDownArrowFunctionKey)!),
      modifiers: [.command, .option])
    add(playback, "Show / Hide Output", #selector(output), "o", modifiers: [.command, .option])
    add(playback, "Restart", #selector(restart), "r", modifiers: [.command, .option])
    let window = menu("Window")
    add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
    NSApp.windowsMenu = window
    NSApp.mainMenu = main
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu.identifier?.rawValue == "CueFlowRecents" else { return }
    menu.removeAllItems()
    for url in NSDocumentController.shared.recentDocumentURLs {
      let item = NSMenuItem(
        title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = url
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let clear = NSMenuItem(
      title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)),
      keyEquivalent: "")
    clear.target = NSDocumentController.shared
    menu.addItem(clear)
  }
  @objc func openRecent(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
      if let error { NSApp.presentError(error) }
    }
  }
  var current: OperatorWindowController? {
    NSApp.keyWindow?.windowController as? OperatorWindowController
      ?? PresentationCoordinator.shared.owner
  }
  @objc func toggle() { current?.toggle() }
  @objc func faster() { current?.adjustSpeed(5) }
  @objc func slower() { current?.adjustSpeed(-5) }
  @objc func output() { current?.showOutput() }
  @objc func restart() { current?.restart() }
}
