import AVFoundation
import CoreMedia
import Foundation
import Speech
import VoiceFollowCore

public struct CapabilityReport: Codable, Sendable {
  public var osVersion: String
  public var transcriberAvailable: Bool
  public var requestedLocale: String
  public var supportedEquivalent: String?
  public var installedLocales: [String]
  public var assetStatus: String
  /// Read only; this experiment never requests speech authorization.
  public var speechAuthorizationStatus: String
}

public enum TranscriptionError: Error, CustomStringConvertible {
  case transcriberUnavailable
  case localeUnsupported(String)
  case assetsNotInstalled(String, status: String)
  case noCompatibleFormat
  case converterFailed(String)

  public var description: String {
    switch self {
    case .transcriberUnavailable:
      "SpeechTranscriber.isAvailable is false on this device; nothing was transcribed."
    case .localeUnsupported(let locale):
      "No SpeechTranscriber locale is equivalent to \(locale); choose an installed English locale."
    case .assetsNotInstalled(let locale, let status):
      "Speech assets for \(locale) are \(status), not installed. This experiment does not download models; "
        + "install them through a separate, explicitly authorized step."
    case .noCompatibleFormat:
      "SpeechAnalyzer reported no compatible audio format for the transcriber."
    case .converterFailed(let detail):
      "Audio conversion to the analyzer format failed: \(detail)"
    }
  }
}

public enum Pacing: String, Codable, Sendable {
  /// File handed to the analyzer as fast as it can process: throughput, not live latency.
  case offline
  /// Buffers delivered no faster than real time; arrival minus audio end approximates
  /// live result latency.
  case realtime
}

public struct TraceResult: Codable, Sendable {
  public var isFinal: Bool
  public var rangeStart: Double
  public var rangeEnd: Double
  public var finalizationTime: Double
  /// Seconds since analysis started (wall clock, monotonic).
  public var arrival: Double
  public var text: String
  public var words: [RecognizedWord]
}

public struct TranscriptionTrace: Codable, Sendable {
  public var schemaVersion = 1
  public var audioFile: String
  public var audioSeconds: Double
  public var pacing: Pacing
  public var locale: String
  public var reportingOptions: [String]
  public var assetStatus: String
  public var localeListedInstalled: Bool
  public var bufferSeconds: Double
  public var prepareSeconds: Double
  public var analysisWallSeconds: Double
  public var cpuSeconds: Double
  public var maxResidentBytes: Int
  public var results: [TraceResult]

  /// Events on the take's audio clock. Real-time traces use measured arrival. Offline traces
  /// keep finals only, idealized as available at their audio end: offline volatile results
  /// observed on macOS 27.0.1 report a range to the end of the file, so they have no usable time.
  public func events() -> [TranscriptEvent] {
    results.filter { pacing == .realtime || $0.isFinal }.map {
      TranscriptEvent(
        isFinal: $0.isFinal, rangeStart: $0.rangeStart, rangeEnd: $0.rangeEnd,
        availableAt: pacing == .realtime ? $0.arrival : $0.rangeEnd, words: $0.words)
    }
  }
}

public enum Probe {
  public static func capabilities(locale identifier: String) async -> CapabilityReport {
    let requested = Locale(identifier: identifier)
    let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested)
    var status = "unsupported"
    if let equivalent {
      let module = SpeechTranscriber(locale: equivalent, preset: .transcription)
      status = String(describing: await AssetInventory.status(forModules: [module]))
    }
    let authorization: String =
      switch SFSpeechRecognizer.authorizationStatus() {
      case .authorized: "authorized"
      case .denied: "denied"
      case .restricted: "restricted"
      case .notDetermined: "notDetermined"
      @unknown default: "unknown"
      }
    return CapabilityReport(
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      transcriberAvailable: SpeechTranscriber.isAvailable, requestedLocale: identifier,
      supportedEquivalent: equivalent?.identifier,
      installedLocales: await SpeechTranscriber.installedLocales.map(\.identifier).sorted(),
      assetStatus: status, speechAuthorizationStatus: authorization)
  }
}

/// Runs SpeechAnalyzer + SpeechTranscriber over a prerecorded file. No microphone, no
/// authorization request and no asset download: missing capability throws instead.
public enum FileTranscriber {
  public static func transcribe(
    audio url: URL, locale identifier: String, pacing: Pacing, fastResults: Bool,
    bufferSeconds: Double = 0.1
  ) async throws -> TranscriptionTrace {
    guard SpeechTranscriber.isAvailable else { throw TranscriptionError.transcriberUnavailable }
    guard
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: identifier))
    else {
      throw TranscriptionError.localeUnsupported(identifier)
    }
    var reporting: Set<SpeechTranscriber.ReportingOption> = [.volatileResults]
    if fastResults { reporting.insert(.fastResults) }
    let transcriber = SpeechTranscriber(
      locale: locale, transcriptionOptions: [], reportingOptions: reporting,
      attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    // On the development Mac, AssetInventory reports `supported` for this module while
    // installedLocales lists the locale. Proceed only on one of the two installed signals; never
    // request installation.
    let status = await AssetInventory.status(forModules: [transcriber])
    let installed = await SpeechTranscriber.installedLocales.contains {
      $0.identifier == locale.identifier
    }
    guard status == .installed || installed else {
      throw TranscriptionError.assetsNotInstalled(
        locale.identifier, status: String(describing: status))
    }
    let file = try AVAudioFile(forReading: url)
    let audioSeconds = Double(file.length) / file.processingFormat.sampleRate
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
      throw TranscriptionError.noCompatibleFormat
    }
    let clock = ContinuousClock()
    let prepareStart = clock.now
    try await analyzer.prepareToAnalyze(in: format)
    let prepareSeconds = seconds(clock.now - prepareStart)
    let usageBefore = ResourceUsage.current()

    let start = clock.now
    let collector = Task {
      var results: [TraceResult] = []
      for try await result in transcriber.results {
        let arrival = seconds(clock.now - start)
        results.append(
          TraceResult(
            isFinal: result.isFinal, rangeStart: result.range.start.seconds,
            rangeEnd: CMTimeRangeGetEnd(result.range).seconds,
            finalizationTime: result.resultsFinalizationTime.seconds, arrival: arrival,
            text: String(result.text.characters), words: words(in: result.text)))
      }
      return results
    }
    switch pacing {
    case .offline:
      if let last = try await analyzer.analyzeSequence(from: file) {
        try await analyzer.finalizeAndFinish(through: last)
      } else {
        await analyzer.cancelAndFinishNow()
      }
    case .realtime:
      let buffers = try convertedBuffers(file: file, to: format, bufferSeconds: bufferSeconds)
      let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
      try await analyzer.start(inputSequence: stream)
      for buffer in buffers {
        // Deliver each buffer once the audio it contains would have been captured live.
        try await clock.sleep(until: start + .seconds(buffer.end))
        continuation.yield(AnalyzerInput(buffer: buffer.pcm, bufferStartTime: buffer.startTime))
      }
      continuation.finish()
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    }
    let results = try await collector.value
    let wall = seconds(clock.now - start)
    let usageAfter = ResourceUsage.current()
    return TranscriptionTrace(
      audioFile: url.lastPathComponent, audioSeconds: audioSeconds, pacing: pacing,
      locale: locale.identifier,
      reportingOptions: reporting.map { String(describing: $0) }.sorted(),
      assetStatus: String(describing: status),
      localeListedInstalled: installed, bufferSeconds: bufferSeconds,
      prepareSeconds: prepareSeconds, analysisWallSeconds: wall,
      cpuSeconds: usageAfter.cpuSeconds - usageBefore.cpuSeconds,
      maxResidentBytes: usageAfter.maxResidentBytes,
      results: results)
  }

  /// Per-run text with its audio range and confidence. Runs that span several words are
  /// split with the run's time range divided by character length.
  static func words(in text: AttributedString) -> [RecognizedWord] {
    var out: [RecognizedWord] = []
    for run in text.runs {
      let runText = String(text[run.range].characters)
      let pieces = runText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard !pieces.isEmpty else { continue }
      // Volatile runs observed on macOS 27.0.1 carry no confidence; -1 marks "not reported".
      let confidence = run.transcriptionConfidence ?? -1
      guard let range = run.audioTimeRange else { continue }
      let start = range.start.seconds
      let duration = range.duration.seconds
      let total = Double(pieces.reduce(0) { $0 + $1.count })
      var offset = 0.0
      for piece in pieces {
        let share = duration * Double(piece.count) / total
        out.append(
          RecognizedWord(
            text: piece, start: start + offset, end: start + offset + share, confidence: confidence)
        )
        offset += share
      }
    }
    return out
  }

  struct TimedBuffer {
    var pcm: AVAudioPCMBuffer
    /// Exact sample-count timestamp; floating-point accumulation makes the analyzer reject
    /// inputs as overlapping (SFSpeechError 17).
    var startTime: CMTime
    var end: Double
  }

  static func convertedBuffers(file: AVAudioFile, to format: AVAudioFormat, bufferSeconds: Double)
    throws
    -> [TimedBuffer]
  {
    let source = file.processingFormat
    guard let converter = AVAudioConverter(from: source, to: format) else {
      throw TranscriptionError.converterFailed("no converter from \(source) to \(format)")
    }
    let inputFrames = AVAudioFrameCount(source.sampleRate * bufferSeconds)
    let outputFrames = AVAudioFrameCount(format.sampleRate * bufferSeconds) + 64
    var buffers: [TimedBuffer] = []
    var producedFrames: Int64 = 0
    file.framePosition = 0
    var finished = false
    while !finished {
      guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: inputFrames),
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrames)
      else { throw TranscriptionError.converterFailed("buffer allocation") }
      try file.read(into: input, frameCount: inputFrames)
      if input.frameLength == 0 { break }
      finished = file.framePosition >= file.length
      var supplied = false
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
        if supplied {
          outStatus.pointee = finished ? .endOfStream : .noDataNow
          return nil
        }
        supplied = true
        outStatus.pointee = .haveData
        return input
      }
      if status == .error {
        throw TranscriptionError.converterFailed(conversionError?.localizedDescription ?? "unknown")
      }
      guard output.frameLength > 0 else { continue }
      let timescale = CMTimeScale(format.sampleRate)
      let startTime = CMTime(value: producedFrames, timescale: timescale)
      producedFrames += Int64(output.frameLength)
      buffers.append(
        TimedBuffer(
          pcm: output, startTime: startTime,
          end: CMTime(value: producedFrames, timescale: timescale).seconds))
    }
    return buffers
  }

  static func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }
}

struct ResourceUsage {
  var cpuSeconds: Double
  var maxResidentBytes: Int

  static func current() -> ResourceUsage {
    var usage = rusage()
    // getrusage(RUSAGE_SELF) fails only for an invalid `who`; report the failure as -1 values.
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
      FileHandle.standardError.write(
        Data("voicefollow: getrusage failed (errno \(errno)); resource figures are -1\n".utf8))
      return ResourceUsage(cpuSeconds: -1, maxResidentBytes: -1)
    }
    let cpu =
      Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
      + Double(usage.ru_stime.tv_sec)
      + Double(usage.ru_stime.tv_usec) / 1e6
    // macOS reports ru_maxrss in bytes.
    return ResourceUsage(cpuSeconds: cpu, maxResidentBytes: Int(usage.ru_maxrss))
  }
}
