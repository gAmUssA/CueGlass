import AVFAudio
import AppKit
import CueFlowCore
import Foundation

struct VoiceLocaleOption: Equatable, Identifiable, Sendable {
  let identifier: String
  let displayName: String
  var id: String { identifier }
}

enum VoiceAssetReadiness: Equatable, Sendable {
  case unavailable
  case unsupportedLocale
  case needsModel
  case downloading
  case ready
}

enum MicrophonePermissionState: Equatable, Sendable {
  case notDetermined
  case denied
  case granted
}

enum VoiceFollowUIState: Equatable {
  case hidden
  case checking
  case unavailable
  case unsupportedLocale
  case needsModel
  case downloading(Double)
  case ready
  case requestingMicrophone
  case microphoneDenied
  case starting
  case listening
  case holding(String)
  case suspended(String)
  case failed(String)
}

@MainActor protocol VoiceCaptureSource: AnyObject {
  func supportedLocales() async -> [VoiceLocaleOption]
  func readiness(localeIdentifier: String) async -> VoiceAssetReadiness
  func install(localeIdentifier: String, reportProgress: @escaping (Double) -> Void) async throws
  func cancelModelInstallation()
  func start(localeIdentifier: String) async throws -> AsyncThrowingStream<
    TranscriptEvent, any Error
  >
  func stop()
}

@MainActor protocol MicrophonePermissionChecking: AnyObject {
  var permission: MicrophonePermissionState { get }
  func requestPermission() async -> Bool
}

@MainActor final class SystemMicrophonePermission: MicrophonePermissionChecking {
  var permission: MicrophonePermissionState {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: .granted
    case .denied: .denied
    case .undetermined: .notDetermined
    @unknown default: .denied
    }
  }

  func requestPermission() async -> Bool {
    await AVAudioApplication.requestRecordPermission()
  }
}

private struct VoiceDecisionEvent: Sendable {
  let epoch: UInt64
  let decision: FollowDecision
}

private actor VoiceAlignmentWorker {
  private var accumulator = TranscriptAccumulator()
  private var policy: FollowPolicy
  private let epoch: UInt64

  init(script: ScriptIndex, startAt tokenIndex: Int, epoch: UInt64) {
    var next = FollowPolicy(script: script)
    next.resume(at: tokenIndex, now: 0)
    policy = next
    self.epoch = epoch
  }

  func ingest(_ event: TranscriptEvent, epoch candidate: UInt64) -> VoiceDecisionEvent? {
    guard candidate == epoch else { return nil }
    accumulator.apply(event)
    let decision = policy.update(hypothesis: accumulator.hypothesis)
    return decision == .none ? nil : VoiceDecisionEvent(epoch: epoch, decision: decision)
  }

  func tick(now: Double, epoch candidate: UInt64) -> VoiceDecisionEvent? {
    guard candidate == epoch else { return nil }
    let decision = policy.tick(now: now)
    return decision == .none ? nil : VoiceDecisionEvent(epoch: epoch, decision: decision)
  }

  func clear() {
    accumulator.clear()
    policy = FollowPolicy(script: policy.script)
  }
}

@MainActor final class VoiceFollowCoordinator {
  private let session: PlaybackSession
  private let source: VoiceCaptureSource
  private let microphone: MicrophonePermissionChecking
  private let usageDescription: () -> String?
  private(set) var state: VoiceFollowUIState = .checking { didSet { onChange?() } }
  private(set) var selectedLocaleIdentifier: String
  private(set) var locales: [VoiceLocaleOption] = [] { didSet { onChange?() } }
  private(set) var installationProgress = 0.0
  var onChange: (() -> Void)?
  private var epoch: UInt64 = 0
  private var worker: VoiceAlignmentWorker?
  private var scriptIndex: ScriptIndex?
  private var lineTable: VoiceLineTable?
  private var sourceStartTask: Task<AsyncThrowingStream<TranscriptEvent, any Error>, any Error>?
  private var captureTask: Task<Void, Never>?
  private var silenceTask: Task<Void, Never>?
  private var installationTask: Task<Void, Never>?
  private var pendingActivationIntent: VoiceStartIntent?
  private var pendingActivationState: VoiceFollowUIState?
  private var readinessState: VoiceFollowUIState = .checking

  init(
    session: PlaybackSession, source: VoiceCaptureSource,
    microphone: MicrophonePermissionChecking = SystemMicrophonePermission(),
    usageDescription: @escaping () -> String?
  ) {
    self.session = session
    self.source = source
    self.microphone = microphone
    self.usageDescription = usageDescription
    let stored = UserDefaults.standard.string(forKey: "voiceFollowLocale")
    selectedLocaleIdentifier = stored ?? Locale.current.identifier
    session.onVoiceStartIntentInvalidated = { [weak self] reason, _ in
      self?.cancelPendingActivation(reason: reason)
    }
    session.onVoicePrioritySuspended = { [weak self] reason, nextEpoch in
      self?.manualOverride(reason: reason, epoch: nextEpoch)
    }
    session.onVoiceEnded = { [weak self] in self?.sessionEndedVoice() }
  }

  var isActive: Bool { session.voiceSessionActive }
  var isSuspended: Bool { session.voiceSessionActive && session.voiceSuspended }

  func selectLocale(_ identifier: String) {
    guard locales.contains(where: { $0.identifier == identifier }),
      identifier != selectedLocaleIdentifier
    else { return }
    if installationTask != nil { cancelInstallation() }
    if session.voiceSessionActive { stop() }
    selectedLocaleIdentifier = identifier
    UserDefaults.standard.set(identifier, forKey: "voiceFollowLocale")
    Task { await refreshAvailability() }
  }

  func refreshAvailability() async {
    readinessState = .checking
    state = readinessState
    let supported = await source.supportedLocales()
    guard !supported.isEmpty else {
      locales = []
      readinessState = .unavailable
      state = readinessState
      return
    }
    locales = supported
    if !supported.contains(where: { $0.identifier == selectedLocaleIdentifier }) {
      selectedLocaleIdentifier = Self.preferredLocale(in: supported)
      UserDefaults.standard.set(selectedLocaleIdentifier, forKey: "voiceFollowLocale")
    }
    let inspectedLocale = selectedLocaleIdentifier
    let readiness = await source.readiness(localeIdentifier: inspectedLocale)
    guard inspectedLocale == selectedLocaleIdentifier else { return }
    readinessState = Self.uiState(for: readiness)
    state = readinessState
  }

  /// Starts the explicitly requested installation. No microphone permission or capture is
  /// requested by this action.
  func installMissingModel() async {
    guard state == .needsModel, installationTask == nil else { return }
    installationProgress = 0
    state = .downloading(0)
    let requestedEpoch = nextEpoch()
    let locale = selectedLocaleIdentifier
    installationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await source.install(localeIdentifier: locale) { [weak self] value in
          guard let self, self.epoch == requestedEpoch else { return }
          installationProgress = min(1, max(0, value))
          state = .downloading(installationProgress)
        }
        guard !Task.isCancelled, epoch == requestedEpoch else { return }
        installationTask = nil
        await refreshAvailability()
      } catch is CancellationError {
        guard epoch == requestedEpoch else { return }
        installationTask = nil
        state = .needsModel
      } catch {
        guard epoch == requestedEpoch else { return }
        installationTask = nil
        state = .failed("Speech model installation failed. Check your connection and try again.")
      }
    }
    await installationTask?.value
  }

  func cancelInstallation() {
    guard installationTask != nil else { return }
    _ = nextEpoch()
    installationTask?.cancel()
    installationTask = nil
    source.cancelModelInstallation()
    state = .needsModel
  }

  func start(
    snapshot: ScriptSnapshot, lineTable: VoiceLineTable, intent: VoiceStartIntent,
    resolveStart: @escaping @MainActor () -> Int?
  ) async {
    await activate(
      snapshot: snapshot, lineTable: lineTable, intent: intent, resolveStart: resolveStart)
  }

  func resume(
    snapshot: ScriptSnapshot, lineTable: VoiceLineTable, intent: VoiceStartIntent,
    resolveStart: @escaping @MainActor () -> Int?
  ) async {
    guard isSuspended else { return }
    await activate(
      snapshot: snapshot, lineTable: lineTable, intent: intent, resolveStart: resolveStart)
  }

  private func activate(
    snapshot: ScriptSnapshot, lineTable: VoiceLineTable, intent: VoiceStartIntent,
    resolveStart: @escaping @MainActor () -> Int?
  )
    async
  {
    guard session.isCurrentVoiceStartIntent(intent), snapshot.id == intent.snapshotID else {
      return
    }
    guard session.canStartVoice else {
      if session.voiceSessionActive && session.voiceSuspended {
        state = .suspended("Switch to Forward before resuming Follow Voice")
      } else {
        state = .failed("Prepare a forward take before starting Follow Voice.")
      }
      return
    }
    guard resolveStart() != nil else {
      state = .failed("Text layout is not ready for Follow Voice.")
      return
    }
    guard let usage = usageDescription(),
      !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      state = .failed(
        "Microphone access is unavailable in this build. Add NSMicrophoneUsageDescription to its Info.plist, then rebuild."
      )
      return
    }
    let requestedEpoch = nextEpoch()
    pendingActivationIntent = intent
    pendingActivationState = state
    defer {
      if pendingActivationIntent == intent {
        pendingActivationIntent = nil
        pendingActivationState = nil
      }
    }
    func currentStartIndex() -> Int? {
      guard epoch == requestedEpoch, pendingActivationIntent == intent,
        session.isCurrentVoiceStartIntent(intent), session.canStartVoice,
        snapshot.id == intent.snapshotID
      else { return nil }
      return resolveStart()
    }

    let locale = selectedLocaleIdentifier
    let readiness = await source.readiness(localeIdentifier: locale)
    guard currentStartIndex() != nil else { return }
    guard readiness == .ready else {
      state = Self.uiState(for: readiness)
      return
    }
    guard currentStartIndex() != nil else { return }
    switch microphone.permission {
    case .denied:
      state = .microphoneDenied
      return
    case .notDetermined:
      state = .requestingMicrophone
      let granted = await microphone.requestPermission()
      guard currentStartIndex() != nil else { return }
      guard granted else {
        state = .microphoneDenied
        return
      }
    case .granted:
      break
    }
    guard let tokenIndex = currentStartIndex() else { return }
    state = .starting
    let index = ScriptIndex(text: snapshot.attributed.string)
    let boundedStart = min(max(tokenIndex, -1), index.count - 1)
    let nextWorker = VoiceAlignmentWorker(
      script: index, startAt: boundedStart, epoch: requestedEpoch)
    worker = nextWorker
    scriptIndex = index
    self.lineTable = lineTable
    do {
      if session.voiceSessionActive {
        try session.resumeVoice(epoch: requestedEpoch)
      } else {
        try session.beginVoice(epoch: requestedEpoch)
      }
      guard currentStartIndex() != nil else {
        source.stop()
        await nextWorker.clear()
        return
      }
      let startTask = Task { try await source.start(localeIdentifier: locale) }
      sourceStartTask = startTask
      let stream = try await startTask.value
      sourceStartTask = nil
      guard currentStartIndex() != nil else {
        source.stop()
        await nextWorker.clear()
        return
      }
      pendingActivationIntent = nil
      pendingActivationState = nil
      state = .listening
      consume(stream, worker: nextWorker, epoch: requestedEpoch)
    } catch {
      guard epoch == requestedEpoch, session.isCurrentVoiceStartIntent(intent) else { return }
      source.stop()
      await nextWorker.clear()
      worker = nil
      scriptIndex = nil
      self.lineTable = nil
      session.endVoice()
      state = .failed("Follow Voice could not start: \(error.localizedDescription)")
    }
  }

  func suspend(reason: String) {
    guard session.voiceSessionActive else { return }
    let next = nextEpoch()
    session.suspendVoice(reason, epoch: next)
    stopCaptureAndClear()
    state = .suspended(reason)
  }

  func stop() {
    session.invalidateVoiceStartIntent("Stop Follow Voice")
    let wasActive = session.voiceSessionActive
    _ = nextEpoch()
    installationTask?.cancel()
    installationTask = nil
    source.cancelModelInstallation()
    source.stop()
    stopTasksAndClearWorker()
    scriptIndex = nil
    lineTable = nil
    if wasActive { session.endVoice() }
    state = stateAfterStop
  }

  private func sessionEndedVoice() {
    _ = nextEpoch()
    pendingActivationIntent = nil
    pendingActivationState = nil
    source.stop()
    stopTasksAndClearWorker()
    scriptIndex = nil
    lineTable = nil
    if case .failed = state { return }
    state = stateAfterStop
  }

  private var stateAfterStop: VoiceFollowUIState {
    microphone.permission == .denied ? .microphoneDenied : readinessState
  }

  func openMicrophoneSettings() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func manualOverride(reason: String, epoch nextEpoch: UInt64) {
    epoch = max(epoch, nextEpoch)
    pendingActivationIntent = nil
    pendingActivationState = nil
    stopCaptureAndClear()
    state = .suspended(reason)
  }

  private func cancelPendingActivation(reason: String) {
    guard pendingActivationIntent != nil else {
      if session.voiceSessionActive && session.voiceSuspended {
        state = .suspended(reason)
      }
      return
    }
    let restoreState = pendingActivationState ?? .ready
    pendingActivationIntent = nil
    pendingActivationState = nil
    _ = nextEpoch()
    sourceStartTask?.cancel()
    sourceStartTask = nil
    if session.voiceSessionActive && session.voiceSuspended {
      state = .suspended(reason)
    } else if !session.voiceSessionActive {
      state = restoreState
    }
  }

  private func stopCaptureAndClear() {
    sourceStartTask?.cancel()
    sourceStartTask = nil
    source.stop()
    stopTasksAndClearWorker()
    scriptIndex = nil
    lineTable = nil
  }

  private func stopTasksAndClearWorker() {
    sourceStartTask?.cancel()
    sourceStartTask = nil
    captureTask?.cancel()
    captureTask = nil
    silenceTask?.cancel()
    silenceTask = nil
    let oldWorker = worker
    worker = nil
    if let oldWorker { Task { await oldWorker.clear() } }
  }

  private func consume(
    _ stream: AsyncThrowingStream<TranscriptEvent, any Error>, worker: VoiceAlignmentWorker,
    epoch streamEpoch: UInt64
  ) {
    captureTask = Task { [weak self] in
      do {
        for try await event in stream {
          guard let self, !Task.isCancelled, epoch == streamEpoch else { return }
          if let result = await worker.ingest(event, epoch: streamEpoch) {
            apply(result)
          }
        }
        guard let self, !Task.isCancelled, epoch == streamEpoch else { return }
        captureFailed("Speech input ended. Start Follow Voice again.", epoch: streamEpoch)
      } catch {
        guard let self, !Task.isCancelled, epoch == streamEpoch else { return }
        captureFailed(
          "Follow Voice stopped after an audio error: \(error.localizedDescription)",
          epoch: streamEpoch)
      }
    }
    let startTime = ProcessInfo.processInfo.systemUptime
    silenceTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard let self, !Task.isCancelled, epoch == streamEpoch else { return }
        let now = ProcessInfo.processInfo.systemUptime - startTime
        if let result = await worker.tick(now: now, epoch: streamEpoch) {
          apply(result)
        }
      }
    }
  }

  private func apply(_ result: VoiceDecisionEvent) {
    guard result.epoch == epoch, session.voiceEpoch == epoch,
      session.voiceSessionActive, !session.voiceSuspended,
      let scriptIndex, let lineTable
    else { return }
    do {
      switch result.decision {
      case .advance(let index):
        guard scriptIndex.tokens.indices.contains(index),
          let y = lineTable.y(for: scriptIndex.tokens[index])
        else { return }
        try session.voiceGlide(to: y, epoch: epoch)
        state = .listening
      case .jump(_, let index):
        guard scriptIndex.tokens.indices.contains(index),
          let y = lineTable.y(for: scriptIndex.tokens[index])
        else { return }
        try session.voiceJump(to: y, epoch: epoch)
        state = .listening
      case .hold(let reason):
        let message = Self.message(for: reason)
        try session.voiceHold(message, epoch: epoch)
        state = .holding(message)
      case .none:
        break
      }
    } catch {
      captureFailed("Follow Voice stopped: \(error.localizedDescription)", epoch: epoch)
    }
  }

  private func captureFailed(_ message: String, epoch failedEpoch: UInt64) {
    guard epoch == failedEpoch else { return }
    _ = nextEpoch()
    source.stop()
    stopTasksAndClearWorker()
    scriptIndex = nil
    lineTable = nil
    session.endVoice()
    state = .failed(message)
  }

  private func nextEpoch() -> UInt64 {
    epoch = max(epoch, session.voiceEpoch) &+ 1
    return epoch
  }

  private static func uiState(for readiness: VoiceAssetReadiness) -> VoiceFollowUIState {
    switch readiness {
    case .unavailable: .unavailable
    case .unsupportedLocale: .unsupportedLocale
    case .needsModel: .needsModel
    case .downloading: .downloading(0)
    case .ready: .ready
    }
  }

  private static func message(for reason: HoldReason) -> String {
    switch reason {
    case .silence: "Waiting for speech"
    case .lowConfidence: "Unsure — holding"
    case .mismatch, .lost: "Trying to reacquire script position"
    case .suspended: "Following paused"
    }
  }

  private static func preferredLocale(in locales: [VoiceLocaleOption]) -> String {
    let current = Locale.current.identifier
    return locales.first(where: {
      Locale(identifier: $0.identifier).language.languageCode?.identifier
        == Locale(identifier: current).language.languageCode?.identifier
    })?.identifier
      ?? locales.first(where: { $0.identifier.hasPrefix("en-") || $0.identifier.hasPrefix("en_") })?
      .identifier
      ?? locales.first?.identifier ?? current
  }
}
