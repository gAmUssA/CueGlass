import AVFAudio
import AppKit
import CueFlowCore
import Speech
import Testing

@testable import CueFlow

@available(macOS 26.0, *)
private final class AudioTapInvocation: @unchecked Sendable {
  private let handler: SpeechAudioTapHandler
  private let buffer: AVAudioPCMBuffer
  private let time: AVAudioTime
  private let lock = NSLock()
  private var ranOnMainThread = true

  init(handler: @escaping SpeechAudioTapHandler, buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    self.handler = handler
    self.buffer = buffer
    self.time = time
  }

  func invoke() {
    lock.lock()
    ranOnMainThread = Thread.isMainThread
    lock.unlock()
    handler(buffer, time)
  }

  func wasCalledOnMainThread() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return ranOnMainThread
  }
}

private struct FakeSpeechAssetError: LocalizedError {
  var errorDescription: String? { "Speech assets are unavailable for this account." }
}

@MainActor private final class FakeVoiceCaptureSource: VoiceCaptureSource {
  var localeOptions = [VoiceLocaleOption(identifier: "en-US", displayName: "English (US)")]
  var readinessState = VoiceAssetReadiness.ready
  var readinessAfterInstallSuccess: VoiceAssetReadiness = .ready
  var readinessAfterInstallError: VoiceAssetReadiness?
  var readinessShouldWait = false
  var installShouldWait = false
  var startShouldWait = false
  var installError: (any Error)?
  private(set) var readinessCount = 0
  private(set) var installCount = 0
  private(set) var cancelInstallCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private var installWaiters: [CheckedContinuation<Void, Never>] = []
  private var installCompletion: CheckedContinuation<Void, any Error>?
  private var readinessWaiters: [CheckedContinuation<Void, Never>] = []
  private var readinessCompletion: CheckedContinuation<VoiceAssetReadiness, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var startCompletion: CheckedContinuation<Void, Never>?
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
    if let installError {
      if let readinessAfterInstallError { readinessState = readinessAfterInstallError }
      throw installError
    }
    readinessState = readinessAfterInstallSuccess
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
    for waiter in startWaiters { waiter.resume() }
    startWaiters.removeAll()
    if startShouldWait {
      await withCheckedContinuation { startCompletion = $0 }
    }
    let pair = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream(
      of: TranscriptEvent.self, bufferingPolicy: .bufferingNewest(4))
    output = pair.continuation
    return pair.stream
  }
  func waitForStart() async {
    if startCount > 0 { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
  func completeStart() {
    startCompletion?.resume()
    startCompletion = nil
  }
  func send(_ event: TranscriptEvent) {
    output?.yield(event)
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

  @Test func captureStartupFinishesBeforeVoiceTimelineBegins() async throws {
    let (session, snapshot, table) = try take()
    var now = 0.0
    session.clock = { now }
    let source = FakeVoiceCaptureSource()
    source.startShouldWait = true
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    let intent = try #require(session.beginVoiceStartIntent())
    let startTask = Task {
      await coordinator.start(
        snapshot: snapshot, lineTable: table, intent: intent, resolveStart: { -1 })
    }

    await source.waitForStart()
    #expect(session.state == .paused)
    #expect(!session.voiceSessionActive)
    now = 2
    source.completeStart()
    await startTask.value

    #expect(session.state == .running)
    #expect(session.voiceSessionActive)
    #expect(session.lastPresentedTarget == 2)
    try session.noteFrame(target: 2.1, end: nil)
    #expect(session.state == .running)
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

  @Test func modelInstallationErrorIsVisibleAndCanBeRetried() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .needsModel
    source.installError = FakeSpeechAssetError()
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    await coordinator.installMissingModel()

    #expect(
      coordinator.state
        == .failed(
          "Speech model installation failed: Speech assets are unavailable for this account. Check your network connection and available storage, then try again."
        ))
    #expect(source.installCount == 1)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)

    source.installError = nil
    source.readinessState = .needsModel
    await coordinator.refreshAvailability()
    #expect(coordinator.state == .needsModel)
  }

  @Test func pendingSystemModelDownloadRemainsCheckableAndDoesNotOpenMicrophone() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .downloading
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    #expect(coordinator.state == .waitingForModel)
    #expect(source.installCount == 0)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)

    source.readinessState = .needsModel
    await coordinator.refreshAvailability()
    #expect(coordinator.state == .needsModel)
  }

  @Test func completedInstallationRequestCanRemainWaitingForSystemAssets() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .needsModel
    source.readinessAfterInstallSuccess = .downloading
    let microphone = FakeMicrophonePermission(.notDetermined)
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: microphone,
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    await coordinator.installMissingModel()

    #expect(coordinator.state == .waitingForModel)
    #expect(source.installCount == 1)
    #expect(microphone.requestCount == 0)
    #expect(source.startCount == 0)
  }

  @Test func audioTapProcessesBuffersFromRealtimeQueue() async throws {
    guard #available(macOS 26.0, *) else { return }
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: false))
    let converter = try #require(AVAudioConverter(from: format, to: format))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
    buffer.frameLength = 512
    if let samples = buffer.int16ChannelData?.pointee {
      samples.update(repeating: 0, count: Int(buffer.frameLength))
    }
    let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(
      of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(2))
    let pipe = AudioInputPipe(
      converter: converter, targetFormat: format, continuation: pair.continuation,
      onError: { _ in })
    let invocation = AudioTapInvocation(
      handler: makeSpeechAudioTapHandler(for: pipe), buffer: buffer,
      time: AVAudioTime(sampleTime: 0, atRate: format.sampleRate))

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        invocation.invoke()
        continuation.resume()
      }
    }

    var iterator = pair.stream.makeAsyncIterator()
    let input = try await iterator.next()
    pair.continuation.finish()
    #expect(input != nil)
    #expect(!invocation.wasCalledOnMainThread())
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
    coordinator.stop()
    #expect(coordinator.state == .microphoneDenied)

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

  @Test func stopTakePreservesMissingModelReadiness() async throws {
    let (session, _, _) = try take()
    let source = FakeVoiceCaptureSource()
    source.readinessState = .needsModel
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.notDetermined),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()

    #expect(coordinator.state == .needsModel)
    coordinator.stop()
    #expect(coordinator.state == .needsModel)
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
    var now = 0.0
    session.clock = { now }
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)
    let listeningEpoch = session.voiceEpoch
    #expect(session.voiceSessionActive)
    #expect(session.state == .running)

    try session.voiceGlide(to: 200, epoch: listeningEpoch)
    now = 2
    _ = try session.position(at: now)
    try session.seek(90)
    #expect(session.voiceSuspended)
    #expect(session.state == .paused)
    #expect(!session.timeline.running)
    #expect(coordinator.state == .suspended("Manual navigation"))
    #expect(source.stopCount == 1)
    #expect(session.timeline.voiceCeiling == nil)
    now += 10
    #expect(try session.position(at: now) == 90)
    try session.voiceGlide(to: 200, epoch: listeningEpoch)
    #expect(session.timeline.anchorPosition == 90)
    try session.toggle(ScriptDocument())
    #expect(session.state == .paused)
    #expect(!session.timeline.running)
    #expect(source.startCount == 1)

    try await start(
      coordinator, session: session, snapshot: snapshot, table: table, token: 1,
      resume: true)
    #expect(!session.voiceSuspended)
    #expect(session.state == .running)
    #expect(session.timeline.running)
    #expect(session.voiceEpoch != listeningEpoch)
    #expect(source.startCount == 2)
    coordinator.stop()
  }

  @Test func spokenPauseKeepsCaptureForResumeAndDoesNotDriveTheScript() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    source.send(transcript("CueGlass pause", startingAt: 1))
    await waitForVoiceState(.commandPaused, coordinator: coordinator)

    #expect(session.voiceSessionActive)
    #expect(session.voiceCommandPaused)
    #expect(!session.voiceSuspended)
    #expect(session.state == .paused)
    #expect(!session.timeline.running)
    #expect(source.stopCount == 0)

    source.send(transcript("North wind carries the lantern", startingAt: 1.5))
    await Task.yield()
    await mainTurn()
    #expect(coordinator.state == .commandPaused)
    #expect(session.state == .paused)
    #expect(source.stopCount == 0)

    source.send(transcript("CueGlass resume", startingAt: 2))
    await waitForVoiceState(.listening, coordinator: coordinator)

    #expect(session.voiceSessionActive)
    #expect(!session.voiceCommandPaused)
    #expect(!session.voiceSuspended)
    #expect(session.state == .running)
    #expect(session.timeline.running)
    #expect(source.stopCount == 0)
    coordinator.stop()
  }

  @Test func commandOnlyRecognitionCarriesTheWakePhraseIntoTheNextUpdate() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    let wake = transcript("CueGlass", startingAt: 1)
    source.send(
      TranscriptEvent(
        isFinal: false, rangeStart: wake.rangeStart, rangeEnd: wake.rangeEnd,
        availableAt: wake.availableAt, words: [], commandAlternatives: [wake.words],
        isCommandOnly: true))
    await Task.yield()
    await mainTurn()
    #expect(coordinator.state == .listening)
    #expect(session.state == .running)

    let action = transcript("pause", startingAt: 1.3)
    source.send(
      TranscriptEvent(
        isFinal: true, rangeStart: action.rangeStart, rangeEnd: action.rangeEnd,
        availableAt: action.availableAt, words: [], commandAlternatives: [action.words],
        isCommandOnly: true))
    await waitForVoiceState(.commandPaused, coordinator: coordinator)

    #expect(session.voiceCommandPaused)
    #expect(session.state == .paused)
    #expect(source.stopCount == 0)
    coordinator.stop()
  }

  @Test func manualNavigationDuringSpokenPauseStillClosesCapture() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    source.send(transcript("CueGlass pause", startingAt: 1))
    await waitForVoiceState(.commandPaused, coordinator: coordinator)
    try session.seek(90)

    #expect(coordinator.state == .suspended("Manual navigation"))
    #expect(session.voiceSuspended)
    #expect(!session.voiceCommandPaused)
    #expect(source.stopCount == 1)
    #expect(session.timeline.anchorPosition == 90)
    coordinator.stop()
  }

  @Test func stopTakeSpeechUsesPlaybackStopAction() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    coordinator.onStopTake = { session.stop() }
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    source.send(transcript("CueGlass stop take", startingAt: 1))
    for _ in 0..<100 where session.state != .idle {
      await Task.yield()
      await mainTurn()
    }

    #expect(session.state == .idle)
    #expect(!session.voiceSessionActive)
    #expect(source.stopCount >= 1)
  }

  @Test func stopFollowingSpeechUsesExistingVoiceStopAction() async throws {
    let (session, snapshot, table) = try take()
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    var stopActionCalled = false
    coordinator.onStopFollowing = { [weak coordinator] in
      stopActionCalled = true
      coordinator?.stop()
    }
    await coordinator.refreshAvailability()
    try await start(coordinator, session: session, snapshot: snapshot, table: table, token: -1)

    source.send(transcript("CueGlass stop following", startingAt: 1))
    await waitForVoiceState(.ready, coordinator: coordinator)

    #expect(stopActionCalled)
    #expect(!session.voiceSessionActive)
    #expect(session.state == .paused)
    #expect(source.stopCount >= 1)
  }

  @Test func stepPaceAndDirectionChangesHoldVoiceTimelineUntilResume() throws {
    for command in ["step", "pace", "direction"] {
      let (session, _, _) = try take()
      var now = 0.0
      session.clock = { now }
      try session.beginVoice(epoch: 7)
      try session.voiceGlide(to: 180, epoch: 7)
      now = 3
      _ = try session.position(at: now)

      switch command {
      case "step": try session.step(forward: true)
      case "pace": try session.speed(60)
      case "direction": try session.reverse()
      default: Issue.record("Unexpected manual command")
      }

      let heldPosition = try session.position(at: now)
      #expect(session.voiceSessionActive)
      #expect(session.voiceSuspended)
      #expect(session.state == .paused)
      #expect(!session.timeline.running)
      #expect(session.timeline.voiceCeiling == nil)
      now += 15
      #expect(try session.position(at: now) == heldPosition)
      try session.voiceGlide(to: 240, epoch: 7)
      #expect(try session.position(at: now) == heldPosition)

      if command != "direction" {
        try session.resumeVoice(epoch: session.voiceEpoch + 1)
        #expect(session.state == .running)
        #expect(session.timeline.running)
        #expect(!session.voiceSuspended)
      }
    }
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

  @Test func confirmedFasterPresenterCadenceRaisesSharedGlideSpeed() async throws {
    let text = "North wind\ncarries the\nlantern home."
    let document = ScriptDocument()
    document.source = NSAttributedString(string: text)
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(document)
    let snapshot = try #require(session.snapshot)
    let sourceText = text as NSString
    let lineTable = VoiceLineTable(
      lines: ["North wind", "carries the", "lantern home."].enumerated().map { index, line in
        let range = sourceText.range(of: line)
        return VoiceLine(
          utf16Range: range.location..<(range.location + range.length), minY: Double(index) * 80)
      })
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    let baseline = session.timeline.velocity
    try await start(
      coordinator, session: session, snapshot: snapshot, table: lineTable, token: -1)

    source.send(transcript("North wind", startingAt: 0))
    source.send(transcript("carries the", startingAt: 0.6))
    for _ in 0..<200 where session.timeline.velocity <= baseline {
      await Task.yield()
      await mainTurn()
    }

    #expect(session.timeline.velocity > baseline)
    #expect(session.timeline.velocity <= baseline * 1.4)
    #expect(session.voiceSessionActive)
    coordinator.stop()
  }

  @Test func volatileTranscriptProgressDoesNotRaiseGlideSpeed() async throws {
    let text = "North wind\ncarries the\nlantern home."
    let document = ScriptDocument()
    document.source = NSAttributedString(string: text)
    let session = PlaybackSession()
    session.clock = { 0 }
    try session.prepare(document)
    let snapshot = try #require(session.snapshot)
    let sourceText = text as NSString
    let lineTable = VoiceLineTable(
      lines: ["North wind", "carries the", "lantern home."].enumerated().map { index, line in
        let range = sourceText.range(of: line)
        return VoiceLine(
          utf16Range: range.location..<(range.location + range.length), minY: Double(index) * 80)
      })
    let source = FakeVoiceCaptureSource()
    let coordinator = VoiceFollowCoordinator(
      session: session, source: source, microphone: FakeMicrophonePermission(.granted),
      usageDescription: { "Mic for voice." })
    await coordinator.refreshAvailability()
    try await start(
      coordinator, session: session, snapshot: snapshot, table: lineTable, token: -1)
    let baseline = session.timeline.velocity

    source.send(transcript("North wind", startingAt: 0, isFinal: false, finalizedThrough: 0))
    source.send(transcript("carries the", startingAt: 0.6, isFinal: false, finalizedThrough: 0))
    for _ in 0..<100 {
      await Task.yield()
      await mainTurn()
    }

    #expect(session.timeline.velocity == baseline)
    coordinator.stop()
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

  private func waitForVoiceState(
    _ expected: VoiceFollowUIState, coordinator: VoiceFollowCoordinator
  ) async {
    for _ in 0..<1000 {
      if coordinator.state == expected { return }
      await Task.yield()
      await mainTurn()
    }
    Issue.record("Follow Voice did not reach state \(expected)")
  }

  private func transcript(
    _ phrase: String, startingAt start: Double, isFinal: Bool = true,
    finalizedThrough: Double? = nil
  ) -> TranscriptEvent {
    let words = phrase.split(whereSeparator: \.isWhitespace).enumerated().map { index, word in
      let wordStart = start + Double(index) * 0.25
      return RecognizedWord(
        text: String(word), start: wordStart, end: wordStart + 0.2, confidence: 0.9)
    }
    return TranscriptEvent(
      isFinal: isFinal,
      rangeStart: words.first?.start ?? start,
      rangeEnd: words.last?.end ?? start,
      availableAt: words.last?.end ?? start,
      words: words,
      finalizedThrough: finalizedThrough)
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
