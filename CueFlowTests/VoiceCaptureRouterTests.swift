import AVFAudio
import CoreAudio
import Testing

@testable import CueFlow

@MainActor private final class FakeInputHost: VoiceAudioInputHost {
  struct Device {
    var id: AudioDeviceID
    var sampleRate: Double
  }
  var devices: [AudioDeviceID: Device]
  var selectedDeviceID: AudioDeviceID
  var refusedDeviceIDs: Set<AudioDeviceID> = []
  /// Formats the host reports before a usable one, to exercise the retry loop.
  var pendingUnusableFormats = 0
  private(set) var selections: [AudioDeviceID] = []
  private(set) var installedFormats: [AVAudioFormat] = []
  private(set) var removedTaps = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var isRunning = false
  private(set) var liveTaps = 0

  init(devices: [Device], selected: AudioDeviceID) {
    self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    selectedDeviceID = selected
  }

  var inputFormat: AVAudioFormat? {
    if pendingUnusableFormats > 0 {
      pendingUnusableFormats -= 1
      return nil
    }
    let rate = devices[selectedDeviceID]?.sampleRate ?? 0
    guard rate > 0 else { return nil }
    return AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
  }
  func selectDevice(_ id: AudioDeviceID) throws {
    selections.append(id)
    if refusedDeviceIDs.contains(id) {
      throw NSError(
        domain: "FakeInputHost", code: Int(id),
        userInfo: [NSLocalizedDescriptionKey: "device \(id) is busy"])
    }
    selectedDeviceID = id
  }
  func installTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) {
    installedFormats.append(format)
    liveTaps += 1
  }
  func removeTap() {
    removedTaps += 1
    liveTaps = max(0, liveTaps - 1)
  }
  func start() throws {
    startCount += 1
    isRunning = true
  }
  func stop() {
    stopCount += 1
    isRunning = false
  }
}

@MainActor private final class FakeInputCatalog: VoiceInputCatalog {
  var options: [VoiceInputDeviceOption]
  var ids: [String: AudioDeviceID]
  var defaultID: AudioDeviceID?
  init(options: [VoiceInputDeviceOption], ids: [String: AudioDeviceID], defaultID: AudioDeviceID?) {
    self.options = options
    self.ids = ids
    self.defaultID = defaultID
  }
  func inputDevices() -> [VoiceInputDeviceOption] { options }
  func deviceID(forUID uid: String) -> AudioDeviceID? { ids[uid] }
  func uid(forDeviceID id: AudioDeviceID) -> String? { ids.first { $0.value == id }?.key }
  func defaultInputDeviceID() -> AudioDeviceID? { defaultID }
}

@Suite(.serialized) @MainActor struct VoiceCaptureRouterTests {
  private let builtIn = VoiceInputDeviceOption(
    uid: "built-in", name: "MacBook Pro Microphone", isDefault: true)
  private let usb = VoiceInputDeviceOption(uid: "usb", name: "USB Microphone", isDefault: false)
  private let builtInID: AudioDeviceID = 41
  private let usbID: AudioDeviceID = 42

  private func fixture(preferred: String?, attachUSB: Bool = true, selected: AudioDeviceID? = nil)
    -> (VoiceCaptureRouter, FakeInputHost, FakeInputCatalog)
  {
    let host = FakeInputHost(
      devices: [
        .init(id: builtInID, sampleRate: 48_000), .init(id: usbID, sampleRate: 44_100),
      ],
      selected: selected ?? builtInID)
    let catalog = FakeInputCatalog(
      options: attachUSB ? [builtIn, usb] : [builtIn],
      ids: attachUSB ? ["built-in": builtInID, "usb": usbID] : ["built-in": builtInID],
      defaultID: builtInID)
    let router = VoiceCaptureRouter(host: host, catalog: catalog, preferredUID: preferred)
    router.sleep = { _ in }
    return (router, host, catalog)
  }

  private func noopTap(_ format: AVAudioFormat) throws -> AVAudioNodeTapBlock { { _, _ in } }

  @Test func openSelectsTheRememberedDeviceAndReportsTheRouteTheUnitAccepted() async throws {
    let (router, host, _) = fixture(preferred: "usb")
    let format = try await router.open()
    #expect(host.selections == [usbID])
    #expect(format.sampleRate == 44_100)
    #expect(router.route?.deviceUID == "usb")
    #expect(router.route?.deviceName == "USB Microphone")
    #expect(router.route?.usesSystemDefault == false)
    #expect(router.route?.failure == nil)
    #expect(router.phase == .preparing)
    #expect(host.liveTaps == 0)
  }

  @Test func systemDefaultAfterAnExplicitDeviceRebindsTheUnitToTheCurrentDefault() async throws {
    let (router, host, _) = fixture(preferred: "usb")
    _ = try await router.open()
    try await router.goLive(tap: noopTap)
    #expect(host.selectedDeviceID == usbID)
    var reported: [VoiceInputRoute] = []
    router.onRouteChanged = { reported.append($0) }

    router.preferredUID = nil
    let applied = try await router.reconfigure()

    #expect(applied)
    #expect(host.selections == [usbID, builtInID])
    #expect(host.selectedDeviceID == builtInID)
    #expect(router.route?.deviceUID == "built-in")
    #expect(router.route?.usesSystemDefault == true)
    #expect(reported.last?.deviceUID == "built-in")
    #expect(host.liveTaps == 1)
    #expect(host.installedFormats.map(\.sampleRate) == [44_100, 48_000])
    #expect(host.isRunning)
  }

  @Test func anAbsentRememberedDeviceFallsBackToTheDefaultExplicitly() async throws {
    let (router, host, _) = fixture(preferred: "usb", attachUSB: false, selected: usbID)
    _ = try await router.open()
    #expect(host.selections == [builtInID])
    #expect(host.selectedDeviceID == builtInID)
    let route = try #require(router.route)
    #expect(route.deviceUID == "built-in")
    #expect(route.usesSystemDefault)
    #expect(route.preferredUnavailable)
    #expect(
      route.notice(preferredName: "USB Microphone")
        == "USB Microphone is not connected — using System Default (MacBook Pro Microphone)")
  }

  @Test func aRefusedSwitchKeepsThePreviousRouteAndReportsTheFailure() async throws {
    let (router, host, _) = fixture(preferred: nil)
    _ = try await router.open()
    try await router.goLive(tap: noopTap)
    host.refusedDeviceIDs = [usbID]

    router.preferredUID = "usb"
    _ = try await router.reconfigure()

    let route = try #require(router.route)
    #expect(host.selectedDeviceID == builtInID)
    #expect(route.deviceUID == "built-in")
    #expect(route.failure == "device 42 is busy")
    #expect(route.usesSystemDefault == false)
    #expect(
      route.notice(preferredName: "USB Microphone")
        == "Could not switch to USB Microphone: device 42 is busy — still using MacBook Pro Microphone"
    )
    #expect(host.liveTaps == 1)
    #expect(host.isRunning)
  }

  @Test func aSelectionDuringPreparationInstallsOneTapWithTheLatestDeviceAndFormat() async throws {
    let (router, host, _) = fixture(preferred: nil)
    let openFormat = try await router.open()
    #expect(openFormat.sampleRate == 48_000)

    router.preferredUID = "usb"
    let applied = try await router.reconfigure()
    #expect(!applied)
    #expect(router.pendingReconfiguration)
    #expect(host.liveTaps == 0)
    #expect(host.startCount == 0)

    let liveFormat = try await router.goLive(tap: noopTap)
    #expect(liveFormat.sampleRate == 44_100)
    #expect(host.selectedDeviceID == usbID)
    #expect(host.liveTaps == 1)
    #expect(host.installedFormats.map(\.sampleRate) == [44_100])
    #expect(host.startCount == 1)
    #expect(router.phase == .live)
    #expect(!router.pendingReconfiguration)
  }

  @Test func aDeviceListChangeDuringPreparationDoesNotInstallACompetingTap() async throws {
    let (router, host, _) = fixture(preferred: nil)
    _ = try await router.open()
    for _ in 0..<3 { _ = try await router.reconfigure() }
    #expect(host.liveTaps == 0)
    #expect(host.removedTaps == 0)
    try await router.goLive(tap: noopTap)
    #expect(host.liveTaps == 1)
    _ = try await router.reconfigure()
    #expect(host.liveTaps == 1)
    #expect(host.removedTaps == 1)
    #expect(host.installedFormats.count == 2)
  }

  @Test func closingDuringPreparationInstallsNoTapAndRefusesALateStart() async throws {
    let (router, host, _) = fixture(preferred: nil)
    _ = try await router.open()
    router.close()
    #expect(router.phase == .closed)
    await #expect(throws: VoiceCaptureRouterError.notPreparing) {
      try await router.goLive(tap: noopTap)
    }
    #expect(host.liveTaps == 0)
    #expect(host.startCount == 0)
    let deferred = try await router.reconfigure()
    #expect(!deferred)
  }

  @Test func closeRemovesTheLiveTapAndStopsTheHost() async throws {
    let (router, host, _) = fixture(preferred: nil)
    _ = try await router.open()
    try await router.goLive(tap: noopTap)
    router.close()
    #expect(host.liveTaps == 0)
    #expect(host.removedTaps == 1)
    #expect(!host.isRunning)
    #expect(router.liveFormat == nil)
  }

  @Test func theFormatRetryWaitsForAUsableFormatAndGivesUpAfterTheAttemptBudget() async throws {
    let (router, host, _) = fixture(preferred: nil)
    host.pendingUnusableFormats = 2
    var sleeps = 0
    router.sleep = { _ in sleeps += 1 }
    let format = try await router.open()
    #expect(format.sampleRate == 48_000)
    #expect(sleeps == 2)

    let (late, lateHost, _) = fixture(preferred: nil)
    lateHost.pendingUnusableFormats = 10
    await #expect(throws: VoiceCaptureRouterError.microphoneFormatUnavailable) {
      try await late.open()
    }
  }
}
