import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@MainActor private final class FakeVoiceCaptureSource: VoiceCaptureSource {
  var localeOptions = [VoiceLocaleOption(identifier: "en-US", displayName: "English (US)")]
  var readinessState = VoiceAssetReadiness.ready
  var installShouldWait = false
  private(set) var installCount = 0
  private(set) var cancelInstallCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var installWaiters: [CheckedContinuation<Void, Never>] = []
  private var installCompletion: CheckedContinuation<Void, any Error>?
  private var output: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?

  func supportedLocales() async -> [VoiceLocaleOption] { localeOptions }
  func readiness(localeIdentifier: String) async -> VoiceAssetReadiness { readinessState }
  func install(localeIdentifier: String, reportProgress: @escaping (Double) -> Void) async throws {
    installCount += 1
    reportProgress(0.35)
    for waiter in installWaiters { waiter.resume() }
    installWaiters.removeAll()
    if installShouldWait {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        installCompletion = continuation
      }
    }
    readinessState = .ready
    reportProgress(1)
  }
  func waitForInstallStart() async {
    if installCount > 0 { return }
    await withCheckedContinuation { installWaiters.append($0) }
  }
  func cancelModelInstallation() {
    cancelInstallCount += 1
    installCompletion?.resume(throwing: CancellationError())
    installCompletion = nil
  }
  func start(localeIdentifier: String) async throws -> AsyncThrowingStream<
    TranscriptEvent, any Error
  > {
    startCount += 1
    let pair = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream(
      of: TranscriptEvent.self, bufferingPolicy: .bufferingNewest(4))
    output = pair.continuation
    return pair.stream
  }
  func stop() {
    stopCount += 1
    output?.finish()
    output = nil
  }
}

@MainActor private final class FakeMicrophonePermission: MicrophonePermissionChecking {
  var permission: MicrophonePermissionState
  var nextRequestResult = true
  private(set) var requestCount = 0

  init(_ permission: MicrophonePermissionState) { self.permission = permission }
  func requestPermission() async -> Bool {
    requestCount += 1
    permission = nextRequestResult ? .granted : .denied
    return nextRequestResult
  }
}

@Suite(.serialized) @MainActor struct VoiceFollowTests {
  init() { _ = NSApplication.shared }

  private func take() throws -> (PlaybackSession, ScriptSnapshot, VoiceLineTable) {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(string: "North wind carries the lantern home.")
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(doc)
    let snapshot = try #require(session.snapshot)
    return (
      session, snapshot,
      VoiceLineTable(lines: [
        VoiceLine(utf16Range: 0..<snapshot.attributed.string.utf16.count, minY: 0)
      ])
    )
  }

  @Test func missingModelRequiresConsentAndDoesNotRequestMicrophone() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .needsModel
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    #expect(coordinator.state == .needsModel)
    #expect(source.installCount == 0)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)

    await coordinator.installMissingModel()
    #expect(coordinator.installationProgress == 1)
    #expect(coordinator.state == .ready)
    #expect(source.installCount == 1)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)

    await coordinator.start(snapshot: snapshot, lineTable: table, startAt: -1)
    #expect(microphone.requestCount == 1)
    #expect(source.startCount == 1)
    #expect(coordinator.state == .listening)
    coordinator.stop()
  }

  @Test func modelInstallationProgressCanBeCancelled() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .needsModel
    source.installShouldWait = true
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.notDetermined),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    let installTask = Task { await coordinator.installMissingModel() }
    await source.waitForInstallStart()
    #expect(coordinator.state == .downloading(0.35))
    coordinator.cancelInstallation()
    await installTask.value

    #expect(source.cancelInstallCount == 1)
    #expect(coordinator.state == .needsModel)
    #expect(!session.voiceSessionActive)
  }

  @Test func deniedMicrophoneNeverStartsCaptureAndMissingUsageTextFailsClosed() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let denied = FakeMicrophonePermission(.denied)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: denied, usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    await coordinator.start(snapshot: snapshot, lineTable: table, startAt: -1)

    #expect(coordinator.state == .microphoneDenied)
    #expect(denied.requestCount == 0)
    #expect(source.startCount == 0)
    #expect(!session.voiceSessionActive)

    let noDescription = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { nil })
    await noDescription.start(snapshot: snapshot, lineTable: table, startAt: -1)
    #expect(source.startCount == 0)
    #expect(
      noDescription.state
        == .failed(
          "Microphone access is unavailable in this build. Add NSMicrophoneUsageDescription to its Info.plist, then rebuild."
        ))
  }

  @Test func unavailableLocaleDoesNotAskForPermissionOrInstallAssets() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .unsupportedLocale
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    #expect(coordinator.locales.map(\.identifier) == ["en-US"])
    #expect(coordinator.state == .unsupportedLocale)
    #expect(source.installCount == 0)
    #expect(source.startCount == 0)
    #expect(microphone.requestCount == 0)
  }

  @Test func manualSeekClosesCaptureAndRejectsStaleVoiceDriveBeforeResume() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    await coordinator.start(snapshot: snapshot, lineTable: table, startAt: -1)
    let listeningEpoch = session.voiceEpoch
    #expect(session.voiceSessionActive)
    #expect(session.state == .running)

    try session.seek(90)
    #expect(session.voiceSuspended)
    #expect(coordinator.state == .suspended("Manual navigation"))
    #expect(source.stopCount == 1)
    #expect(session.timeline.voiceCeiling == nil)
    try session.voiceGlide(to: 200, epoch: listeningEpoch)
    #expect(session.timeline.anchorPosition == 90)

    await coordinator.resume(snapshot: snapshot, lineTable: table, startAt: 1)
    #expect(!session.voiceSuspended)
    #expect(session.voiceEpoch != listeningEpoch)
    #expect(source.startCount == 2)
    coordinator.stop()
  }

  @Test func sharedVoiceDriveIsSpeedCappedAndTimedScrollingStopsVoice() async throws {
    let (session, _, _) = try take()
    session.configuredMax = 240
    try session.updateLayout(end: 1000, paragraphs: [], wordCount: 8, lineCount: 1)
    try session.speed(240)
    session.configuredMax = 60
    try session.beginVoice(epoch: 4)

    #expect(session.effectiveLPM <= session.configuredMax)
    #expect(session.timedDuration == nil)
    try session.voiceGlide(to: 200, epoch: 4)
    session.clock = { 10 }
    #expect(try session.position(at: 10) == 200)
    #expect(try session.position(at: 20) == 200)

    try session.enableTimed(seconds: 60)
    #expect(!session.voiceSessionActive)
    #expect(session.timeline.voiceCeiling == nil)
    #expect(session.timedDuration == 60)
    #expect(session.state == .running)
  }

  @Test func textKitBuildsAndInvalidatesTheVoiceLineMapWithItsLayout() async throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: "A 🐈 bright line wraps across a narrow column.\nNext sentence begins here.")
    let controller = OperatorWindowController(document: doc)
    controller.session.clock = { 0 }
    try controller.session.prepare(doc)
    controller.render()
    for _ in 0..<2000 where controller.session.measuring {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    let original = try #require(controller.authoritative.voiceLineTable)
    let script = ScriptIndex(text: try #require(controller.session.snapshot).attributed.string)
    let first = try #require(original.y(for: script.tokens[0]))
    let last = try #require(original.y(for: script.tokens.last!))
    #expect(first >= 0)
    #expect(last >= first)

    var style = controller.state.style
    style.fontSize = 76
    controller.changeStyle(style)
    for _ in 0..<2000 where controller.session.measuring {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
    }
    let updated = try #require(controller.authoritative.voiceLineTable)
    #expect(updated != original)
    #expect(updated.lines.last?.minY != original.lines.last?.minY)
    controller.close()
  }

  @Test func followVoiceSurfaceIsUnavailableBeforeMacOS26() {
    if #unavailable(macOS 26.0) {
      let controller = OperatorWindowController(document: ScriptDocument())
      #expect(!controller.state.voiceAvailable)
      #expect(controller.state.voiceState == .hidden)
      controller.close()
    }
  }
}
