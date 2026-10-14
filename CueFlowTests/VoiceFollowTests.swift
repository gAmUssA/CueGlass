import AppKit
import CueFlowCore
import Testing

@testable import CueFlow

@MainActor private final class FakeVoiceCaptureSource: VoiceCaptureSource {
  var localeOptions = [VoiceLocaleOption(identifier: "en-US", displayName: "English (US)")]
  var readinessState = VoiceAssetReadiness.ready
  var readinessShouldWait = false
  var installShouldWait = false
  private(set) var readinessCount = 0
  private(set) var installCount = 0
  private(set) var cancelInstallCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var installWaiters: [CheckedContinuation<Void, Never>] = []
  private var installCompletion: CheckedContinuation<Void, any Error>?
  private var readinessWaiters: [CheckedContinuation<Void, Never>] = []
  private var readinessCompletion: CheckedContinuation<VoiceAssetReadiness, Never>?
  private var output: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?

  func supportedLocales() async -> [VoiceLocaleOption] { localeOptions }
  func readiness(localeIdentifier: String) async -> VoiceAssetReadiness {
    readinessCount += 1
    for waiter in readinessWaiters { waiter.resume() }
    readinessWaiters.removeAll()
    if readinessShouldWait {
      return await withCheckedContinuation { readinessCompletion = $0 }
    }
    return readinessState
  }
  func waitForReadinessRequest(after count: Int) async {
    if readinessCount > count { return }
    await withCheckedContinuation { readinessWaiters.append($0) }
  }
  func completeReadiness(_ readiness: VoiceAssetReadiness = .ready) {
    readinessState = readiness
    readinessCompletion?.resume(returning: readiness)
    readinessCompletion = nil
  }
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
  var requestShouldWait = false
  private(set) var requestCount = 0
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var requestCompletion: CheckedContinuation<Bool, Never>?

  init(_ permission: MicrophonePermissionState) { self.permission = permission }
  func requestPermission() async -> Bool {
    requestCount += 1
    for waiter in requestWaiters { waiter.resume() }
    requestWaiters.removeAll()
    if requestShouldWait {
      return await withCheckedContinuation { requestCompletion = $0 }
    }
    permission = nextRequestResult ? .granted : .denied
    return nextRequestResult
  }
  func waitForRequest(after count: Int = 0) async {
    if requestCount > count { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }
  func completeRequest(_ granted: Bool) {
    permission = granted ? .granted : .denied
    requestCompletion?.resume(returning: granted)
    requestCompletion = nil
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

    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)
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
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    #expect(coordinator.state == .microphoneDenied)
    #expect(denied.requestCount == 0)
    #expect(source.startCount == 0)
    #expect(!session.voiceSessionActive)

    let noDescription = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { nil })
    try await start(
      noDescription, session: session, snapshot: snapshot, table: table, token: -1)
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
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)
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

    try await start(
      coordinator, session: session, snapshot: snapshot, table: table, token: 1,
      resume: true)
    #expect(!session.voiceSuspended)
    #expect(session.voiceEpoch != listeningEpoch)
    #expect(source.startCount == 2)
    coordinator.stop()
  }

  @Test func stopDuringMeasuredVoiceStartThenOrdinaryPlayDoesNotStartVoice() async throws {
    let doc = ScriptDocument()
    doc.source = NSAttributedString(
      string: (0..<200).map { "Paragraph \($0) alpha beta gamma delta epsilon" }.joined(
        separator: "\n"))
    let controller = OperatorWindowController(document: doc)
    defer { controller.close() }
    controller.session.clock = { 0 }
    controller.state.countdown = 0
    controller.voiceCoordinator?.stop()
    let source = FakeVoiceCaptureSource()
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: controller.session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    controller.voiceCoordinator = coordinator
    await coordinator.refreshAvailability()

    controller.startVoiceFollow()
    #expect(controller.session.measuring)
    controller.stop()
    controller.state.countdown = 0
    controller.toggle()
    #expect(controller.session.measuring)
    await settle(controller)
    await mainTurn()

    #expect(controller.session.state == .running)
    #expect(!controller.session.voiceSessionActive)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)
  }

  @Test func stopOrManualOverrideBeforeQueuedStartupTaskDoesNotOpenCapture() async throws {
    for stop in [true, false] {
      let doc = ScriptDocument()
      doc.source = NSAttributedString(string: "North wind carries the lantern home.")
      let controller = OperatorWindowController(document: doc)
      defer { controller.close() }
      controller.session.clock = { 0 }
      controller.voiceCoordinator?.stop()
      let source = FakeVoiceCaptureSource()
      let microphone = FakeMicrophonePermission(.notDetermined)
      let coordinator = VoiceFollowCoordinator(
        session: controller.session, source: source, microphone: microphone,
        usageDescription: { "Mic for voice." })
      controller.voiceCoordinator = coordinator
      await coordinator.refreshAvailability()

      controller.startVoiceFollow()
      #expect(!controller.session.measuring)
      if stop {
        controller.stopVoiceFollow()
      } else {
        try controller.session.seek(90)
      }
      await mainTurn()
      await mainTurn()

      #expect(microphone.requestCount == 0)
      #expect(source.startCount == 0)
      #expect(!controller.session.voiceSessionActive)
      #expect(controller.session.timeline.anchorPosition == (stop ? 0 : 90))
    }
  }

  @Test func manualNavigationDuringDeferredReadinessDoesNotRequestMicrophone() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    let readinessCount = source.readinessCount
    source.readinessShouldWait = true
    let intent = try #require(session.beginVoiceStartIntent())
    let startTask = Task {
      await coordinator.start(
        snapshot: snapshot, lineTable: table, intent: intent, resolveStart: { -1 })
    }
    await source.waitForReadinessRequest(after: readinessCount)

    try session.seek(90)
    source.completeReadiness()
    await startTask.value

    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)
    #expect(!session.voiceSessionActive)
    #expect(session.timeline.anchorPosition == 90)
  }

  @Test func manualNavigationDuringDeferredPermissionDoesNotStartCapture() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let microphone = FakeMicrophonePermission(.notDetermined)
    microphone.requestShouldWait = true
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    let intent = try #require(session.beginVoiceStartIntent())
    let startTask = Task {
      await coordinator.start(
        snapshot: snapshot, lineTable: table, intent: intent, resolveStart: { -1 })
    }
    await microphone.waitForRequest()

    try session.seek(90)
    microphone.completeRequest(true)
    await startTask.value

    #expect(microphone.requestCount == 1)
    #expect(source.startCount == 0)
    #expect(!session.voiceSessionActive)
    #expect(session.timeline.anchorPosition == 90)
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

  @Test func followVoiceSurfaceUsesPlatformCapability() {
    for majorVersion in [14, 25] {
      let capability = VoiceFollowPlatformCapability(
        majorVersion: majorVersion, speechTranscriberAvailable: true)
      #expect(!capability.allowsVoiceFollow)
      let unsupported = OperatorWindowController(
        document: ScriptDocument(), voiceCapabilityOverride: capability)
      #expect(!unsupported.state.voiceAvailable)
      #expect(unsupported.state.voiceState == .hidden)
      #expect(unsupported.voiceCoordinator == nil)
      unsupported.close()
    }

    let supportedCapability = VoiceFollowPlatformCapability(
      majorVersion: 26, speechTranscriberAvailable: true)
    #expect(supportedCapability.allowsVoiceFollow)
    let unsupportedSpeechCapability = VoiceFollowPlatformCapability(
      majorVersion: 26, speechTranscriberAvailable: false)
    #expect(!unsupportedSpeechCapability.allowsVoiceFollow)
    if #available(macOS 26.0, *) {
      let supported = OperatorWindowController(
        document: ScriptDocument(), voiceCapabilityOverride: supportedCapability)
      #expect(supported.state.voiceAvailable)
      #expect(supported.voiceCoordinator != nil)
      supported.close()

      let unsupportedSpeech = OperatorWindowController(
        document: ScriptDocument(), voiceCapabilityOverride: unsupportedSpeechCapability)
      #expect(!unsupportedSpeech.state.voiceAvailable)
      #expect(unsupportedSpeech.state.voiceState == .hidden)
      #expect(unsupportedSpeech.voiceCoordinator == nil)
      unsupportedSpeech.close()
    }
  }

  private func mainTurn() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func settle(_ controller: OperatorWindowController) async {
    for _ in 0..<2000 {
      if !controller.session.measuring { return }
      await mainTurn()
    }
    Issue.record("Measurement did not settle in 2000 main queue turns")
  }

  private func start(
    _ coordinator: VoiceFollowCoordinator, session: PlaybackSession, snapshot: ScriptSnapshot,
    table: VoiceLineTable, token: Int, resume: Bool = false
  ) async throws {
    let intent = try #require(session.beginVoiceStartIntent())
    if resume {
      await coordinator.resume(
        snapshot: snapshot, lineTable: table, intent: intent, resolveStart: { token })
    } else {
      await coordinator.start(
        snapshot: snapshot, lineTable: table, intent: intent, resolveStart: { token })
    }
  }
}
