import AVFAudio
import CoreAudio
import Foundation

/// The microphone that is actually feeding capture, read back from the input unit after a
/// selection rather than inferred from the device list.
struct VoiceInputRoute: Equatable, Sendable {
  /// UID of the device the input unit reports; nil when no input device exists.
  var deviceUID: String?
  var deviceName: String?
  /// No specific device is applied; the system default is in use.
  var usesSystemDefault: Bool
  /// The remembered device is not attached, so the system default was selected instead.
  var preferredUnavailable: Bool
  /// The requested device refused selection; capture stayed on `deviceUID`.
  var failure: String?

  /// Operator-facing explanation when the route differs from the remembered choice.
  func notice(preferredName: String?) -> String? {
    if let failure {
      let target = preferredName ?? "the selected microphone"
      let actual = deviceName.map { " — still using \($0)" } ?? ""
      return "Could not switch to \(target): \(failure)\(actual)"
    }
    if preferredUnavailable {
      let target = preferredName ?? "The selected microphone"
      let actual = deviceName.map { " (\($0))" } ?? ""
      return "\(target) is not connected — using System Default\(actual)"
    }
    return nil
  }
}

/// One input bus of an audio engine, as the router needs it. `AVAudioEngine` conforms
/// through `EngineInputHost`; tests substitute a fake to drive routing and tap ownership.
@MainActor protocol VoiceAudioInputHost: AnyObject {
  /// The bus format; nil or a zero-rate format means the device is not ready yet.
  var inputFormat: AVAudioFormat? { get }
  var selectedDeviceID: AudioDeviceID { get }
  func selectDevice(_ id: AudioDeviceID) throws
  func installTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock)
  func removeTap()
  func start() throws
  func stop()
  var isRunning: Bool { get }
}

@MainActor protocol VoiceInputCatalog: AnyObject {
  func inputDevices() -> [VoiceInputDeviceOption]
  func deviceID(forUID uid: String) -> AudioDeviceID?
  func uid(forDeviceID id: AudioDeviceID) -> String?
  func defaultInputDeviceID() -> AudioDeviceID?
}

@MainActor final class SystemInputCatalog: VoiceInputCatalog {
  func inputDevices() -> [VoiceInputDeviceOption] { AudioInputDeviceCatalog.inputDevices() }
  func deviceID(forUID uid: String) -> AudioDeviceID? {
    AudioInputDeviceCatalog.deviceID(forUID: uid)
  }
  func uid(forDeviceID id: AudioDeviceID) -> String? {
    AudioInputDeviceCatalog.uid(forDeviceID: id)
  }
  func defaultInputDeviceID() -> AudioDeviceID? { AudioInputDeviceCatalog.defaultInputDeviceID() }
}

@MainActor final class EngineInputHost: VoiceAudioInputHost {
  private let engine: AVAudioEngine
  init(engine: AVAudioEngine) { self.engine = engine }
  var inputFormat: AVAudioFormat? { engine.inputNode.inputFormat(forBus: 0) }
  var selectedDeviceID: AudioDeviceID { engine.inputNode.auAudioUnit.deviceID }
  func selectDevice(_ id: AudioDeviceID) throws {
    try engine.inputNode.auAudioUnit.setDeviceID(id)
  }
  func installTap(format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) {
    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
  }
  func removeTap() { engine.inputNode.removeTap(onBus: 0) }
  func start() throws { try engine.start() }
  func stop() { engine.stop() }
  var isRunning: Bool { engine.isRunning }
}

enum VoiceCaptureRouterError: LocalizedError, Equatable {
  case microphoneFormatUnavailable
  case notPreparing

  var errorDescription: String? {
    switch self {
    case .microphoneFormatUnavailable:
      "The microphone did not provide a usable audio format."
    case .notPreparing:
      "Capture was closed before it could start."
    }
  }
}

/// Owns the input route and the single tap of one capture: which device the bus uses, when
/// the tap is installed, and how a device change is applied. Startup and reconfiguration
/// go through one phase machine, so a selection made while the analyzer is still
/// preparing is folded into the first tap instead of installing a second one.
@MainActor final class VoiceCaptureRouter {
  enum Phase: Equatable { case idle, preparing, live, closed }
  typealias TapFactory = (AVAudioFormat) throws -> AVAudioNodeTapBlock

  private(set) var phase = Phase.idle
  private(set) var route: VoiceInputRoute?
  private(set) var liveFormat: AVAudioFormat?
  private(set) var tapInstalled = false
  private(set) var pendingReconfiguration = false
  var preferredUID: String?
  var onRouteChanged: ((VoiceInputRoute) -> Void)?
  /// Device enumeration and the input format can lag a hot-plug by a few hundred ms.
  var formatAttempts = 5
  var formatRetryDelay: Duration = .milliseconds(150)
  /// Startup applies at most this many requests that arrive during its format waits
  /// before installing the tap; a later one goes through the live path once.
  var startupReconfigurationBudget = 4
  var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

  private let host: any VoiceAudioInputHost
  private let catalog: any VoiceInputCatalog
  private var tapFactory: TapFactory?

  init(host: any VoiceAudioInputHost, catalog: any VoiceInputCatalog, preferredUID: String?) {
    self.host = host
    self.catalog = catalog
    self.preferredUID = preferredUID
  }

  /// Applies the route and waits for a usable input format. The capture is then preparing:
  /// device changes are recorded and applied when it goes live.
  func open() async throws -> AVAudioFormat {
    guard phase == .idle else { throw VoiceCaptureRouterError.notPreparing }
    phase = .preparing
    applyRoute()
    return try await usableInputFormat()
  }

  /// Installs the one tap and starts the host. A reconfiguration requested during
  /// preparation is applied first, so the tap uses the latest device and format. A
  /// request that arrives while the format wait is suspended is applied by another pass
  /// before the tap goes in; the pass count is bounded so a stream of requests cannot
  /// starve startup, and a request past that bound is applied by the live path instead.
  @discardableResult
  func goLive(tap: @escaping TapFactory) async throws -> AVAudioFormat {
    guard phase == .preparing else { throw VoiceCaptureRouterError.notPreparing }
    tapFactory = tap
    var format: AVAudioFormat
    var passes = 0
    repeat {
      if pendingReconfiguration {
        pendingReconfiguration = false
        applyRoute()
      }
      format = try await usableInputFormat()
      passes += 1
    } while pendingReconfiguration && passes < startupReconfigurationBudget
    guard phase == .preparing else { throw VoiceCaptureRouterError.notPreparing }
    try installTap(format: format, using: tap)
    try host.start()
    phase = .live
    if pendingReconfiguration {
      pendingReconfiguration = false
      _ = try await reconfigure()
      format = liveFormat ?? format
    }
    return format
  }

  /// Applies the current `preferredUID` and format. Returns false when the change was
  /// deferred (capture still preparing) or capture is not open.
  @discardableResult
  func reconfigure() async throws -> Bool {
    switch phase {
    case .preparing:
      pendingReconfiguration = true
      return false
    case .idle, .closed:
      return false
    case .live:
      break
    }
    guard let tapFactory else { return false }
    host.removeTap()
    tapInstalled = false
    if host.isRunning { host.stop() }
    applyRoute()
    let format = try await usableInputFormat()
    guard phase == .live, !Task.isCancelled else { return false }
    try installTap(format: format, using: tapFactory)
    try host.start()
    return true
  }

  func close() {
    phase = .closed
    pendingReconfiguration = false
    if host.isRunning { host.stop() }
    if tapInstalled {
      host.removeTap()
      tapInstalled = false
    }
    tapFactory = nil
    liveFormat = nil
  }

  private func installTap(format: AVAudioFormat, using factory: TapFactory) throws {
    if tapInstalled { host.removeTap() }
    let block = try factory(format)
    host.installTap(format: format, block: block)
    tapInstalled = true
    liveFormat = format
  }

  /// Selects the remembered device, or the current system default when none is remembered
  /// or it is absent, then reads back what the bus actually uses.
  private func applyRoute() {
    let devices = catalog.inputDevices()
    let resolvedUID = VoiceInputSelection.resolve(preferredUID: preferredUID, available: devices)
    let preferredUnavailable = (preferredUID?.isEmpty == false) && resolvedUID == nil
    let target =
      resolvedUID.flatMap { catalog.deviceID(forUID: $0) } ?? catalog.defaultInputDeviceID()
    var failure: String?
    if let target, target != host.selectedDeviceID {
      do {
        try host.selectDevice(target)
      } catch {
        failure = error.localizedDescription
      }
    }
    let actualUID = catalog.uid(forDeviceID: host.selectedDeviceID)
    let next = VoiceInputRoute(
      deviceUID: actualUID,
      deviceName: devices.first { $0.uid == actualUID }?.name,
      usesSystemDefault: resolvedUID == nil,
      preferredUnavailable: preferredUnavailable,
      failure: failure)
    guard next != route else { return }
    route = next
    onRouteChanged?(next)
  }

  private static func isUsable(_ format: AVAudioFormat?) -> Bool {
    guard let format else { return false }
    return format.sampleRate > 0 && format.channelCount > 0
  }

  private func usableInputFormat() async throws -> AVAudioFormat {
    var attempt = 0
    while true {
      if let format = host.inputFormat, Self.isUsable(format) { return format }
      attempt += 1
      guard attempt < formatAttempts else {
        throw VoiceCaptureRouterError.microphoneFormatUnavailable
      }
      try await sleep(formatRetryDelay)
      guard phase == .preparing || phase == .live else {
        throw VoiceCaptureRouterError.notPreparing
      }
    }
  }
}
