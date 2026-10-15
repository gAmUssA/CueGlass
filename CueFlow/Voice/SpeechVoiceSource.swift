import AVFAudio
import AVFoundation
import CoreMedia
import CueFlowCore
import Foundation
import Speech

@available(macOS 26.0, *)
@MainActor final class SpeechVoiceSource: VoiceCaptureSource {
  private var engine: AVAudioEngine?
  private var analyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var inputContinuation: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?
  private var outputContinuation: AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?
  private var inputPipe: AudioInputPipe?
  private var analyzerTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var configurationObserver: NSObjectProtocol?
  private var installationRequest: AssetInstallationRequest?
  private var captureStartedAt = 0.0

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
    switch await AssetInventory.status(forModules: [module]) {
    case .installed:
      let installed = await SpeechTranscriber.installedLocales
      return installed.contains(where: { $0.identifier == locale.identifier })
        ? .ready : .needsModel
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
    let request = try await AssetInventory.assetInstallationRequest(
      supporting: [makeTranscriber(locale: locale)])
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

  func start(localeIdentifier: String) async throws -> AsyncThrowingStream<
    TranscriptEvent, any Error
  > {
    guard await readiness(localeIdentifier: localeIdentifier) == .ready else {
      throw VoiceSourceError.modelNotReady
    }
    try Task.checkCancellation()
    stop()

    let module = makeTranscriber(locale: Locale(identifier: localeIdentifier))
    let analyzer = SpeechAnalyzer(
      modules: [module],
      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse))
    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    else { throw VoiceSourceError.noCompatibleAudioFormat }
    try Task.checkCancellation()

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.inputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
      let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    else { throw VoiceSourceError.microphoneFormatUnavailable }

    let inputPair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(
      of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(24))
    let outputPair = AsyncThrowingStream<TranscriptEvent, any Error>.makeStream(
      of: TranscriptEvent.self, bufferingPolicy: .bufferingNewest(12))
    let pipe = AudioInputPipe(
      converter: converter, targetFormat: targetFormat, continuation: inputPair.continuation
    ) { [weak self] error in
      Task { @MainActor in self?.failAudio(error) }
    }
    self.engine = engine
    self.analyzer = analyzer
    self.transcriber = module
    inputContinuation = inputPair.continuation
    outputContinuation = outputPair.continuation
    inputPipe = pipe

    try await analyzer.prepareToAnalyze(in: targetFormat)
    try Task.checkCancellation()
    analyzerTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: inputPair.stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        self?.finishOutput()
      } catch {
        self?.finishOutput(throwing: error)
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
          if !event.words.isEmpty { outputPair.continuation.yield(event) }
        }
        guard !Task.isCancelled else { return }
        outputPair.continuation.finish()
      } catch {
        outputPair.continuation.finish(throwing: error)
      }
      self?.finishHardwareAfterResults()
    }

    inputNode.installTap(
      onBus: 0, bufferSize: 1024, format: inputFormat,
      block: makeSpeechAudioTapHandler(for: pipe))
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.failAudio(VoiceSourceError.audioConfigurationChanged) }
    }
    do {
      try Task.checkCancellation()
      try engine.start()
    } catch {
      stop()
      throw error
    }
    return outputPair.stream
  }

  func stop() {
    if let engine {
      if engine.isRunning { engine.stop() }
      engine.inputNode.removeTap(onBus: 0)
    }
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
    analyzerTask = nil
    resultsTask = nil
    if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    engine = nil
    analyzer = nil
    transcriber = nil
    captureStartedAt = 0
  }

  private func failAudio(_ error: Error) {
    inputContinuation?.finish(throwing: error)
    outputContinuation?.finish(throwing: error)
    stopHardware()
  }

  private func finishOutput(throwing error: (any Error)? = nil) {
    if let error {
      outputContinuation?.finish(throwing: error)
    } else {
      outputContinuation?.finish()
    }
  }

  private func finishHardwareAfterResults() {
    stopHardware()
  }

  private func stopHardware() {
    if let engine {
      if engine.isRunning { engine.stop() }
      engine.inputNode.removeTap(onBus: 0)
    }
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
      self.configurationObserver = nil
    }
    inputContinuation?.finish()
    inputContinuation = nil
    inputPipe = nil
    analyzerTask?.cancel()
    resultsTask?.cancel()
    analyzerTask = nil
    resultsTask = nil
    if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    engine = nil
    analyzer = nil
    transcriber = nil
  }

  private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .fastResults],
      attributeOptions: [.audioTimeRange, .transcriptionConfidence])
  }

  private nonisolated static func event(
    from result: SpeechTranscriber.Result, availableAt: Double
  ) -> TranscriptEvent {
    var words: [RecognizedWord] = []
    for run in result.text.runs {
      guard let time = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else {
        continue
      }
      let transcript = String(result.text[run.range].characters)
      let start = time.start.seconds
      let end = CMTimeGetSeconds(CMTimeRangeGetEnd(time))
      guard start.isFinite, end.isFinite, end >= start else { continue }
      let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] ?? -1
      for word in transcript.split(whereSeparator: \.isWhitespace) {
        words.append(
          RecognizedWord(text: String(word), start: start, end: end, confidence: confidence))
      }
    }
    return TranscriptEvent(
      isFinal: result.isFinal,
      rangeStart: result.range.start.seconds,
      rangeEnd: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),
      availableAt: availableAt,
      words: words)
  }
}

@available(macOS 26.0, *)
final class AudioInputPipe: @unchecked Sendable {
  private let converter: AVAudioConverter
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

  func append(_ input: AVAudioPCMBuffer) {
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
    case .audioConfigurationChanged: "The audio input device changed or disconnected."
    case .bufferConversionFailed: "Microphone audio could not be prepared for transcription."
    case .inputStreamTerminated: "The microphone audio stream is no longer available."
    }
  }
}
