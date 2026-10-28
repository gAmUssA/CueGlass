import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@Suite(.serialized) @MainActor struct PolishTests {
  init() { _ = NSApplication.shared }

  @Test func playbackCommandTitles() {
    #expect(PlaybackCommand.toggle.title == "Play / Pause")
    #expect(PlaybackCommand.faster.title == "Faster")
    #expect(PlaybackCommand.slower.title == "Slower")
    #expect(PlaybackCommand.jumpFaster.title == "Faster (large step)")
    #expect(PlaybackCommand.jumpSlower.title == "Slower (large step)")
    #expect(PlaybackCommand.nextParagraph.title == "Next Paragraph")
    #expect(PlaybackCommand.previousParagraph.title == "Previous Paragraph")
    #expect(PlaybackCommand.restart.title == "Restart")
    #expect(PlaybackCommand.reverse.title == "Reverse Direction")
    #expect(PlaybackCommand.exit.title == "Stop Presenting")
    #expect(PlaybackCommand.cameraDock.title == "Camera Dock")
    #expect(PlaybackCommand.allCases.count == 11)
  }

  @Test func newDocumentKeepsTheWelcomePrefix() {
    let text = ScriptDocument().source.string
    #expect(text.hasPrefix("Welcome to CueGlass"))
    #expect(text.contains("choose File ▸ Open…"))
    #expect(text.contains("Then press Play in the toolbar."))
    #expect(!text.contains("Import a TXT"))
  }

  @Test func localBuildHidesICloudMenusAndWindowMenuHasStandardItems() throws {
    let previousMenu = NSApp.mainMenu
    let previousWindows = NSApp.windowsMenu
    let delegate = AppDelegate()
    delegate.buildMenu()
    defer {
      NSApp.mainMenu = previousMenu
      NSApp.windowsMenu = previousWindows
    }
    let main = try #require(NSApp.mainMenu)
    let file = try #require(main.items.first { $0.title == "File" }?.submenu)
    let cloudTitles = ["Save to iCloud…", "Request iCloud Download", "Refresh iCloud Status"]
    for title in cloudTitles {
      let item = try #require(file.items.first { $0.title == title })
      item.target = delegate
    }
    file.update()
    for title in cloudTitles {
      let item = try #require(file.items.first { $0.title == title })
      #expect(item.isHidden)
      #expect(!delegate.validateMenuItem(item))
    }
    #expect(AppDelegate.showsICloudMenus("") == false)
    #expect(AppDelegate.showsICloudMenus("iCloud.com.example.cueflow"))
    let window = try #require(main.items.first { $0.title == "Window" }?.submenu)
    #expect(window.items.contains { $0.title == "Zoom" })
    #expect(window.items.contains { $0.title == "Bring All to Front" })
    let playback = try #require(main.items.first { $0.title == "Playback" }?.submenu)
    #expect(playback.items.contains { $0.title == "Present" })
    #expect(!playback.items.contains { $0.title == "Show / Hide Output" })
  }

  @Test func operatorCopySaysPresent() {
    #expect(OperatorControls.presentTabTitle == "Present")
    #expect(OperatorControls.previewWhilePresentingTitle == "Preview while presenting")
    #expect(OperatorWindowController.unnamedPresentSurface == "Present")
    #expect(
      OperatorWindowController.presentDisplayDisconnectedRetained
        == "Present display disconnected — position retained")
    #expect(
      OperatorWindowController.presentingStoppedRetained
        == "Presenting stopped — position retained")
    #expect(
      OperatorWindowController.presentDisplayDisconnectedChoose
        == "Present display disconnected — choose a display")
    #expect(
      OperatorWindowController.previewCaption(
        screen: nil, size: CGSize(width: 1280, height: 720), mirrored: false)
        == "Present preview · Local 1280 × 720 · exact present layout, scaled · shown unmirrored")
  }

  @Test func operatorScreenAlertUsesStopPresenting() {
    #expect(
      OperatorWindowController.presentOnOperatorScreenNotice
        == "This screen will be covered. Press Escape or choose Stop Presenting to return.")
  }
}
