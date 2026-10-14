import AVFoundation
import Foundation
import VoiceFollowCore

public enum FixtureStep: Sendable {
  case sentences(ClosedRange<Int>)
  /// Last `count` words of a sentence (a short repeat).
  case tail(sentence: Int, count: Int)
  case adlib(String)
  case silence(Double)
}

public struct FixtureVariant: Sendable {
  public var name: String
  public var voice: String
  public var rate: Int
  public var steps: [FixtureStep]
}

public struct FixtureManifest: Codable, Sendable {
  public var schemaVersion = 1
  public var variant: String
  public var audioFile: String
  public var voice: String
  public var rate: Int
  public var sampleRate: Double
  public var durationSeconds: Double
  public var sentenceGapSeconds: Double
  public var synthesizer: String
  public var hostOS: String
  public var provenance: String
  public var segments: [TruthSegment]
}

public enum FixtureError: Error, CustomStringConvertible {
  case sayFailed(status: Int32, text: String)
  case audio(String)

  public var description: String {
    switch self {
    case .sayFailed(let status, let text):
      "/usr/bin/say exited \(status) for \"\(text)\"; check that the voice is installed (say -v '?')."
    case .audio(let detail): "Fixture audio error: \(detail)"
    }
  }
}

/// Synthesizes owned script audio with preinstalled macOS voices. Each sentence is spoken
/// separately and trimmed, so every speech segment's start and end are known exactly.
public enum FixtureMaker {
  public static let sampleRate = 16_000.0
  public static let sentenceGap = 0.35

  public static let variants: [FixtureVariant] = [
    FixtureVariant(name: "verbatim", voice: "Samantha", rate: 175, steps: [.sentences(0...11)]),
    FixtureVariant(
      name: "silence", voice: "Samantha", rate: 175,
      steps: [.sentences(0...4), .silence(5), .sentences(5...8)]),
    FixtureVariant(
      name: "repeat", voice: "Samantha", rate: 175,
      steps: [
        .sentences(0...4), .tail(sentence: 4, count: 5), .sentences(5...6), .sentences(3...4),
        .sentences(7...8),
      ]),
    FixtureVariant(
      name: "skip", voice: "Samantha", rate: 175, steps: [.sentences(0...5), .sentences(9...11)]),
    FixtureVariant(
      name: "adlib", voice: "Samantha", rate: 175,
      steps: [
        .sentences(0...3),
        .adlib(
          "Before we go on, let me say that my grandmother kept a light like this one for many years."
        ),
        .sentences(4...7),
      ]),
    FixtureVariant(name: "fast", voice: "Samantha", rate: 230, steps: [.sentences(0...11)]),
    FixtureVariant(name: "daniel", voice: "Daniel", rate: 185, steps: [.sentences(0...11)]),
  ]

  public static func make(variant: FixtureVariant, script: ScriptIndex, directory: URL) throws
    -> FixtureManifest
  {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    var samples: [Float] = []
    var segments: [TruthSegment] = []
    var time: Double { Double(samples.count) / sampleRate }
    let scratch = directory.appendingPathComponent("segments-\(variant.name)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    var counter = 0

    func speak(_ text: String, kind: TruthSegment.Kind, tokens: Range<Int>?) throws {
      if !samples.isEmpty {
        let gapStart = time
        samples.append(contentsOf: repeatElement(0, count: Int(sentenceGap * sampleRate)))
        segments.append(TruthSegment(kind: .silence, start: gapStart, end: time))
      }
      counter += 1
      let url = scratch.appendingPathComponent(String(format: "%03d.wav", counter))
      try say(text, voice: variant.voice, rate: variant.rate, to: url)
      let audio = trimmed(try read(url, format: format))
      let start = time
      samples.append(contentsOf: audio)
      segments.append(
        TruthSegment(
          kind: kind, start: start, end: time, scriptFirst: tokens?.lowerBound,
          scriptLast: tokens.map { $0.upperBound - 1 }, text: text))
    }

    for step in variant.steps {
      switch step {
      case .sentences(let range):
        for index in range {
          let tokens = script.sentences[index]
          try speak(script.text(of: tokens), kind: .speech, tokens: tokens)
        }
      case .tail(let sentence, let count):
        let full = script.sentences[sentence]
        let tokens = (full.upperBound - count)..<full.upperBound
        try speak(script.text(of: tokens), kind: .speech, tokens: tokens)
      case .adlib(let text):
        try speak(text, kind: .adlib, tokens: nil)
      case .silence(let seconds):
        let start = time
        samples.append(contentsOf: repeatElement(0, count: Int(seconds * sampleRate)))
        segments.append(TruthSegment(kind: .silence, start: start, end: time))
      }
    }
    let trailing = time
    samples.append(contentsOf: repeatElement(0, count: Int(1.0 * sampleRate)))
    segments.append(TruthSegment(kind: .silence, start: trailing, end: time))

    let audioName = "\(variant.name).wav"
    try write(samples, format: format, to: directory.appendingPathComponent(audioName))
    try FileManager.default.removeItem(at: scratch)
    return FixtureManifest(
      variant: variant.name, audioFile: audioName, voice: variant.voice, rate: variant.rate,
      sampleRate: sampleRate,
      durationSeconds: time, sentenceGapSeconds: sentenceGap, synthesizer: "/usr/bin/say",
      hostOS: ProcessInfo.processInfo.operatingSystemVersionString,
      provenance:
        "Generated locally from DemoScript (written for this experiment) and the ad-lib text in FixtureMaker; "
        + "/usr/bin/say -v \(variant.voice) -r \(variant.rate) per segment, LEI16@16000 WAVE, "
        + "edges trimmed at |sample| < 0.01, \(sentenceGap) s gaps inserted.",
      segments: segments)
  }

  static func say(_ text: String, voice: String, rate: Int, to url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = [
      "-v", voice, "-r", String(rate), "-o", url.path, "--file-format=WAVE",
      "--data-format=LEI16@16000", text,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw FixtureError.sayFailed(status: process.terminationStatus, text: text)
    }
  }

  static func read(_ url: URL, format: AVAudioFormat) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard file.processingFormat.sampleRate == format.sampleRate,
      file.processingFormat.channelCount == 1
    else {
      throw FixtureError.audio(
        "unexpected format \(file.processingFormat) for \(url.lastPathComponent)")
    }
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else { throw FixtureError.audio("cannot allocate \(file.length) frames") }
    try file.read(into: buffer)
    return Array(
      UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
  }

  static func trimmed(_ audio: [Float], threshold: Float = 0.01) -> [Float] {
    guard let first = audio.firstIndex(where: { abs($0) >= threshold }),
      let last = audio.lastIndex(where: { abs($0) >= threshold })
    else { return [] }
    return Array(audio[first...last])
  }

  static func write(_ samples: [Float], format: AVAudioFormat, to url: URL) throws {
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(
      forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
    else {
      throw FixtureError.audio("cannot allocate output buffer")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer {
      buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
  }
}
