import AVFAudio
import AVFoundation
import CoreMedia
import CueFlowCore
import Foundation
import Speech

struct CaptureGenerationGate: Sendable {
  private(set) var requestGeneration: UInt64 = 0
  private(set) var activeGeneration: UInt64?

  mutating func beginRequest() -> UInt64 {
    requestGeneration &+= 1
    activeGeneration = nil
    return requestGeneration
  }

  mutating func activate(_ generation: UInt64) -> Bool {
    guard isCurrentRequest(generation) else { return false }
    activeGeneration = generation
    return true
  }

  mutating func invalidate() {
    requestGeneration &+= 1
    activeGeneration = nil
  }

  mutating func deactivate() { activeGeneration = nil }

  func isCurrentRequest(_ generation: UInt64) -> Bool {
    requestGeneration == generation
  }

  func acceptsCallback(_ generation: UInt64) -> Bool {
    requestGeneration == generation && activeGeneration == generation
  }
}

@available(macOS 26.0, *)
@MainActor final class SpeechVoiceSource: VoiceCaptureSource {
  private var engine: AVAudioEngine?
  private var analyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var commandTranscriber: DictationTranscriber?
  private var inputContinuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?
  private var outputContinuation: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?
  private var inputPipe: AudioInputPipe?
  private var analyzerTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var commandResultsTask: Task<Void, Never>?
  private var configurationObserver: NSObjectProtocol?
  private var installationRequest: AssetInstallationRequest?
  private var captureStartedAt = 0.0
  private var resultStreamsRemaining = 0
  private var captureGeneration = CaptureGenerationGate()
  private var router: VoiceCaptureRouter?
  private var preferredInputDeviceUID: String?
  private var deviceObserver: AudioInputDeviceObserver?
  private var routeHandler: (@MainActor (VoiceInputRoute?) -> Void)?
  private var reconfiguration: Task<Void, Never>?
  /// The analyzer keeps up in real time; this only has to absorb a reconfiguration stall.
  static let inputBufferLimit = 256

  var inputRoute: VoiceInputRoute? { router?.route }

  func observeInputRoute(_ handler: @escaping @MainActor (VoiceInputRoute?) -> Void) {
    routeHandler = handler
  }

  func supportedLocales() async -> [VoiceLocaleOption] {
    guard SpeechTranscriber.isAvailable else { return [] }
    return await SpeechTranscriber.supportedLocales
      .map {
        VoiceLocaleOption(
          identifier: $0.identifier,
          displayName: $0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
      }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }

  func readiness(localeIdentifier: String) async -> VoiceAssetReadiness {
    guard SpeechTranscriber.isAvailable else { return .unavailable }
    let locale = Locale(identifier: localeIdentifier)
    let supported = await SpeechTranscriber.supportedLocales
    guard supported.contains(where: { $0.identifier == locale.identifier }) else {
      return .unsupportedLocale
    }
    let module = makeTranscriber(locale: locale)
    let commandModule = await makeCommandTranscriber(localeIdentifier: localeIdentifier)
    var modules: [any SpeechModule] = [module]
    if let commandModule { modules.append(commandModule) }
    switch await AssetInventory.status(forModules: modules) {
    case .installed:
      let installed = await SpeechTranscriber.installedLocales
      guard installed.contains(where: { $0.identifier == locale.identifier }) else {
        return .needsModel
      }
      if commandModule != nil {
        let commandInstalled = await DictationTranscriber.installedLocales
        guard
          commandInstalled.contains(where: {
            $0.identifier == commandModule?.selectedLocales.first?.identifier
          })
        else { return .needsModel }
      }
      return .ready
    case .downloading:
      return .downloading
    case .supported:
      return .needsModel
    case .unsupported:
      return .unavailable
    @unknown default:
      return .unavailable
    }
  }

  func install(localeIdentifier: String, reportProgress: @escaping (Double) -> Void) async throws {
    let locale = Locale(identifier: localeIdentifier)
    guard await readiness(localeIdentifier: localeIdentifier) == .needsModel else { return }
    var modules: [any SpeechModule] = [makeTranscriber(locale: locale)]
    if let commandModule = await makeCommandTranscriber(localeIdentifier: localeIdentifier) {
      modules.append(commandModule)
    }
    let request = try await AssetInventory.assetInstallationRequest(
      supporting: modules)
    try Task.checkCancellation()
    // AssetInventory returns nil when the required assets are already installed. Let the
    // coordinator recheck readiness instead of presenting that normal race as a failure.
    guard let request else { return }
    installationRequest = request
    let progressTask = Task { @MainActor in
      while !Task.isCancelled {
        reportProgress(request.progress.fractionCompleted)
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
      }
    }
    defer {
      progressTask.cancel()
      installationRequest = nil
    }
    try await request.downloadAndInstall()
    reportProgress(1)
  }

  func cancelModelInstallation() {
    installationRequest?.progress.cancel()
    installationRequest = nil
  }

  func availableInputDevices() -> [VoiceInputDeviceOption] {
    AudioInputDeviceCatalog.inputDevices()
  }

  /// Remembers the microphone to open. While capture is running, the engine switches to it in
  /// place; the analyzer, transcript stream, and the take all stay where they are.
  func setPreferredInputDevice(uid: String?) {
    let next = uid.flatMap { $0.isEmpty ? nil : $0 }
    let changed = next != preferredInputDeviceUID
    preferredInputDeviceUID = next
    guard let router, let generation = captureGeneration.activeGeneration else { return }
    router.preferredUID = next
    // A device-list change can move the system default or bring the remembered device
    // back, so the route is re-applied even when the remembered choice is unchanged.
    _ = changed
    scheduleReconfiguration(generation: generation)
  }

  func observeInputDevices(_ handler: @escaping @MainActor () -> Void) {
    deviceObserver = AudioInputDeviceObserver(handler)
  }

  func start(localeIdentifier: String) async throws -> AsyncThrowingStream<
    TranscriptEvent, any Error
  > {
    let generation = captureGeneration.beginRequest()
    stopCurrentCapture()
    guard await readiness(localeIdentifier: localeIdentifier) == .ready else {
      throw VoiceSourceError.modelNotReady
    }
    try ensureCurrentRequest(generation)
    try Task.checkCancellation()

    let module = makeTranscriber(locale: Locale(identifier: localeIdentifier))
    let commandModule = await makeCommandTranscriber(localeIdentifier: localeIdentifier)
    try ensureCurrentRequest(generation)
    var modules: [any SpeechModule] = [module]
    if let commandModule { modules.append(commandModule) }
    let analyzer = SpeechAnalyzer(
      modules: modules,
      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse))
    if commandModule != nil {
      let context = AnalysisContext()
      context.contextualStrings[.general] = [
        "CueGlass", "Cue Glass", "Prompter", "pause", "resume", "stop take", "stop following",
      ]
      try await analyzer.setContext(context)
      try ensureCurrentRequest(generation)
    }
    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
    else { throw VoiceSourceError.noCompatibleAudioFormat }
    try ensureCurrentRequest(generation)
    try Task.checkCancellation()

    let engine = AVAudioEngine()
    let router = VoiceCaptureRouter(
      host: EngineInputHost(engine: engine), catalog: SystemInputCatalog(),
      preferredUID: preferredInputDeviceUID)
    router.onRouteChanged = { [weak self] route in self?.routeHandler?(route) }
    guard captureGeneration.activate(generation) else { throw CancellationError() }
    self.engine = engine
    self.router = router
    let inputFormat: AVAudioFormat
    do {
      inputFormat = try await router.open()
      try ensureCurrentRequest(generation)
    } catch {
      if captureGeneration.acceptsCallback(generation) { stopCurrentCapture() }
      throw error
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      stopCurrentCapture()
      throw VoiceSourceError.microphoneFormatUnavailable
    }

    let inputPair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(
      of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(Self.inputBufferLimit))
    let outputPair = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream(
      of: TranscriptEvent.self, bufferingPolicy: .bufferingNewest(32))
    let pipe = AudioInputPipe(
      converter: converter, targetFormat: targetFormat, continuation: inputPair.continuation
    ) { [weak self] error in
      Task { @MainActor in self?.failAudio(error, generation: generation) }
    }
    self.analyzer = analyzer
    self.transcriber = module
    self.commandTranscriber = commandModule
    inputContinuation = inputPair.continuation
    outputContinuation = outputPair.continuation
    inputPipe = pipe
    resultStreamsRemaining = commandModule == nil ? 1 : 2
    // Plugging, unplugging, or switching a microphone changes the input's sample rate or
    // channel count; the engine stops and posts this. The router rebuilds the tap on the
    // new format — or folds the change into startup while the analyzer is still preparing —
    // and the analyzer and transcript stream keep running instead of ending the session.
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.scheduleReconfiguration(generation: generation) }
    }

    do {
      try await analyzer.prepareToAnalyze(in: targetFormat)
      try ensureCurrentRequest(generation)
      try Task.checkCancellation()
      analyzerTask = Task { [weak self] in
        do {
          try await analyzer.start(inputSequence: inputPair.stream)
          try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          self?.failResultStream(error, generation: generation)
        }
      }
      let captureStartedAt = ProcessInfo.processInfo.systemUptime
      self.captureStartedAt = captureStartedAt
      resultsTask = Task { [weak self] in
        do {
          for try await result in module.results {
            guard !Task.isCancelled else { return }
            let event = Self.event(
              from: result, availableAt: ProcessInfo.processInfo.systemUptime - captureStartedAt)
            // Empty results can advance finalization without repeating their volatile wording.
            if !event.words.isEmpty || !(event.commandAlternatives ?? []).isEmpty || event.isFinal
              || event.finalizedThrough?.isFinite == true
            {
              outputPair.continuation.yield(event)
            }
          }
          guard !Task.isCancelled else { return }
          self?.resultStreamFinished(generation: generation)
        } catch {
          guard !Task.isCancelled, !(error is CancellationError) else { return }
          self?.failResultStream(error, generation: generation)
        }
      }
      if let commandModule {
        commandResultsTask = Task { [weak self] in
          do {
            for try await result in commandModule.results {
              guard !Task.isCancelled else { return }
              let event = Self.commandEvent(
                from: result, availableAt: ProcessInfo.processInfo.systemUptime - captureStartedAt)
              if !(event.commandAlternatives ?? []).isEmpty || event.isFinal
                || event.finalizedThrough?.isFinite == true
              {
                outputPair.continuation.yield(event)
              }
            }
            guard !Task.isCancelled else { return }
            self?.resultStreamFinished(generation: generation)
          } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self?.failResultStream(error, generation: generation)
          }
        }
      }

      try ensureCurrentRequest(generation)
      try Task.checkCancellation()
      // One owner installs the one tap: a device switched during preparation is applied
      // here, with its own format, before the tap goes in.
      try await router.goLive(tap: Self.tapFactory(for: pipe, targetFormat: targetFormat))
      try ensureCurrentRequest(generation)
      return outputPair.stream
    } catch {
      if captureGeneration.acceptsCallback(generation) { stopCurrentCapture() }
      throw error
    }
  }

  func stop() {
    captureGeneration.invalidate()
    stopCurrentCapture()
  }

  private func stopCurrentCapture() {
    captureGeneration.deactivate()
    reconfiguration?.cancel()
    reconfiguration = nil
    router?.close()
    router = nil
    if routeHandler != nil { routeHandler?(nil) }
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
      self.configurationObserver = nil
    }
    inputContinuation?.finish()
    outputContinuation?.finish()
    inputContinuation = nil
    outputContinuation = nil
    inputPipe = nil
    analyzerTask?.cancel()
    resultsTask?.cancel()
    commandResultsTask?.cancel()
    analyzerTask = nil
    resultsTask = nil
    commandResultsTask = nil
    if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    engine = nil
    analyzer = nil
    transcriber = nil
    commandTranscriber = nil
    resultStreamsRemaining = 0
    captureStartedAt = 0
  }

  /// Builds the tap for a (possibly new) input format: the pipe swaps its converter and the
  /// same real-time handler feeds the analyzer, so the sample clock keeps counting.
  private static func tapFactory(
    for pipe: AudioInputPipe, targetFormat: AVAudioFormat
  ) -> VoiceCaptureRouter.TapFactory {
    { inputFormat in
      guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
        throw VoiceSourceError.microphoneFormatUnavailable
      }
      pipe.replaceConverter(converter)
      return makeSpeechAudioTapHandler(for: pipe)
    }
  }

  private func scheduleReconfiguration(generation: UInt64) {
    guard captureGeneration.acceptsCallback(generation) else { return }
    reconfiguration?.cancel()
    reconfiguration = Task { @MainActor [weak self] in
      await self?.reconfigureCapture(generation: generation)
    }
  }

  /// Rebuilds only the audio input: same engine, same analyzer, same transcript stream.
  /// While startup is still preparing the router records the change and applies it when the
  /// tap goes in, so startup and reconfiguration never install competing taps.
  private func reconfigureCapture(generation: UInt64) async {
    guard captureGeneration.acceptsCallback(generation), let router else { return }
    do {
      _ = try await router.reconfigure()
    } catch is CancellationError {
      return
    } catch {
      guard captureGeneration.acceptsCallback(generation) else { return }
      failAudio(error, generation: generation)
    }
  }

  private func ensureCurrentRequest(_ generation: UInt64) throws {
    guard captureGeneration.isCurrentRequest(generation) else { throw CancellationError() }
  }

  private func failAudio(_ error: Error, generation: UInt64) {
    guard captureGeneration.acceptsCallback(generation), !(error is CancellationError)
    else { return }
    inputContinuation?.finish(throwing: error)
    outputContinuation?.finish(throwing: error)
    stopCurrentCapture()
  }

  private func resultStreamFinished(generation: UInt64) {
    guard captureGeneration.acceptsCallback(generation) else { return }
    resultStreamsRemaining = max(0, resultStreamsRemaining - 1)
    guard resultStreamsRemaining == 0 else { return }
    outputContinuation?.finish()
    stopCurrentCapture()
  }

  private func failResultStream(_ error: any Error, generation: UInt64) {
    guard captureGeneration.acceptsCallback(generation), !(error is CancellationError)
    else { return }
    outputContinuation?.finish(throwing: error)
    stopCurrentCapture()
  }

  private func makeCommandTranscriber(localeIdentifier: String) async -> DictationTranscriber? {
    let requestedLocale = Locale(identifier: localeIdentifier)
    guard requestedLocale.language.languageCode?.identifier == "en",
      let supportedLocale = await DictationTranscriber.supportedLocale(
        equivalentTo: requestedLocale)
    else { return nil }
    return DictationTranscriber(
      locale: supportedLocale,
      contentHints: [.shortForm],
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .alternativeTranscriptions],
      attributeOptions: [.audioTimeRange, .transcriptionConfidence])
  }

  private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .fastResults, .alternativeTranscriptions],
      attributeOptions: [.audioTimeRange, .transcriptionConfidence])
  }

  private nonisolated static func event(
    from result: SpeechTranscriber.Result, availableAt: Double
  ) -> TranscriptEvent {
    let words = recognizedWords(in: result.text)
    let commandAlternatives = result.alternatives.dropFirst().prefix(3).map {
      Array(recognizedWords(in: $0, fallbackRange: result.range).suffix(4))
    }.filter { !$0.isEmpty }
    return TranscriptEvent(
      isFinal: result.isFinal,
      rangeStart: result.range.start.seconds,
      rangeEnd: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),
      availableAt: availableAt,
      words: words,
      finalizedThrough: result.resultsFinalizationTime.seconds,
      commandAlternatives: commandAlternatives)
  }

  private nonisolated static func commandEvent(
    from result: DictationTranscriber.Result, availableAt: Double
  ) -> TranscriptEvent {
    let best = Array(recognizedWords(in: result.text, fallbackRange: result.range).suffix(4))
    let alternatives =
      ([best]
      + result.alternatives.dropFirst().prefix(2).map {
        Array(recognizedWords(in: $0, fallbackRange: result.range).suffix(4))
      }).filter { !$0.isEmpty }
    return TranscriptEvent(
      isFinal: result.isFinal,
      rangeStart: result.range.start.seconds,
      rangeEnd: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),
      availableAt: availableAt,
      words: [],
      finalizedThrough: result.resultsFinalizationTime.seconds,
      commandAlternatives: alternatives,
      isCommandOnly: true)
  }

  private nonisolated static func recognizedWords(
    in text: AttributedString, fallbackRange: CMTimeRange? = nil
  ) -> [RecognizedWord] {
    var words: [RecognizedWord] = []
    for run in text.runs {
      guard let time = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else {
        continue
      }
      let transcript = String(text[run.range].characters)
      let start = time.start.seconds
      let end = CMTimeGetSeconds(CMTimeRangeGetEnd(time))
      guard start.isFinite, end.isFinite, end >= start else { continue }
      let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] ?? -1
      for word in transcript.split(whereSeparator: \.isWhitespace) {
        words.append(
          RecognizedWord(text: String(word), start: start, end: end, confidence: confidence))
      }
    }
    if words.isEmpty, let fallbackRange {
      let transcript = String(text.characters)
      let start = fallbackRange.start.seconds
      let end = CMTimeGetSeconds(CMTimeRangeGetEnd(fallbackRange))
      guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        start.isFinite, end.isFinite, end >= start
      else { return words }
      return transcript.split(whereSeparator: \.isWhitespace).map {
        RecognizedWord(text: String($0), start: start, end: end, confidence: -1)
      }
    }
    return words
  }
}

@available(macOS 26.0, *)
final class AudioInputPipe: @unchecked Sendable {
  private let lock = NSLock()
  private var converter: AVAudioConverter
  private let targetFormat: AVAudioFormat
  private let continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation
  private let onError: @Sendable (any Error) -> Void
  private var nextSampleTime: Int64 = 0

  init(
    converter: AVAudioConverter, targetFormat: AVAudioFormat,
    continuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation,
    onError: @escaping @Sendable (any Error) -> Void
  ) {
    self.converter = converter
    self.targetFormat = targetFormat
    self.continuation = continuation
    self.onError = onError
  }

  /// Swaps the converter when the input device or its format changes; the output format and
  /// the running sample clock are unchanged.
  func replaceConverter(_ next: AVAudioConverter) {
    lock.lock()
    converter = next
    lock.unlock()
  }

  func append(_ input: AVAudioPCMBuffer) {
    lock.lock()
    let converter = self.converter
    lock.unlock()
    let scaledCapacity =
      ceil(
        Double(input.frameLength) * targetFormat.sampleRate / input.format.sampleRate) + 64
    guard scaledCapacity.isFinite, scaledCapacity > 0,
      let output = AVAudioPCMBuffer(
        pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(scaledCapacity))
    else {
      onError(VoiceSourceError.bufferConversionFailed)
      return
    }
    let oneShotInput = OneShotAudioInput(input)
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
      guard let input = oneShotInput.take() else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      inputStatus.pointee = .haveData
      return input
    }
    if let conversionError {
      onError(conversionError)
      return
    }
    guard status != .error else {
      onError(VoiceSourceError.bufferConversionFailed)
      return
    }
    guard output.frameLength > 0 else { return }
    let sampleRate = CMTimeScale(targetFormat.sampleRate.rounded())
    let start = CMTime(value: nextSampleTime, timescale: sampleRate)
    nextSampleTime += Int64(output.frameLength)
    if case .terminated = continuation.yield(
      AnalyzerInput(buffer: output, bufferStartTime: start))
    {
      onError(VoiceSourceError.inputStreamTerminated)
    }
  }
}

@available(macOS 26.0, *)
typealias SpeechAudioTapHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

/// AVAudioNode calls tap handlers from its audio messenger queue. Keep this closure in a
/// nonisolated file-level factory so it doesn't inherit SpeechVoiceSource's MainActor isolation.
@available(macOS 26.0, *)
func makeSpeechAudioTapHandler(for pipe: AudioInputPipe) -> SpeechAudioTapHandler {
  { buffer, _ in pipe.append(buffer) }
}

@available(macOS 26.0, *)
private final class OneShotAudioInput: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: AVAudioPCMBuffer?

  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

  func take() -> AVAudioPCMBuffer? {
    lock.lock()
    defer { lock.unlock() }
    let buffer = self.buffer
    self.buffer = nil
    return buffer
  }
}

@available(macOS 26.0, *)
private enum VoiceSourceError: LocalizedError {
  case modelNotReady
  case noCompatibleAudioFormat
  case microphoneFormatUnavailable
  case audioConfigurationChanged
  case bufferConversionFailed
  case inputStreamTerminated

  var errorDescription: String? {
    switch self {
    case .modelNotReady: "The selected speech model is not installed and ready."
    case .noCompatibleAudioFormat: "No audio format is available for this speech model."
    case .microphoneFormatUnavailable: "The microphone did not provide a usable audio format."
    case .audioConfigurationChanged: "The audio input device changed and could not be reopened."
    case .bufferConversionFailed: "Microphone audio could not be prepared for transcription."
    case .inputStreamTerminated: "The microphone audio stream is no longer available."
    }
  }
}
