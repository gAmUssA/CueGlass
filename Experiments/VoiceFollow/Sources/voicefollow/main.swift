import Foundation
import VoiceFollowCore
import VoiceFollowSpeech

let usage = """
  usage: voicefollow <command> [options]
    probe [--locale en_US]                       read-only SpeechTranscriber capability report
    make-fixtures --out DIR [--only NAME]        synthesize owned TTS fixtures with /usr/bin/say
    transcribe --audio FILE --out TRACE.json [--pacing offline|realtime] [--fast] [--locale en_US]
    evaluate --trace TRACE.json --manifest MANIFEST.json [--out EVAL.json]
    synthetic                                    deterministic transcript scenarios, no audio
  """

struct UsageError: Error, CustomStringConvertible {
  var description: String
}

func option(_ name: String, in args: [String]) -> String? {
  guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
  return args[index + 1]
}

func required(_ name: String, in args: [String]) throws -> String {
  guard let value = option(name, in: args) else {
    throw UsageError(description: "missing \(name)\n\(usage)")
  }
  return value
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

func emit<T: Encodable>(_ value: T, to path: String?) throws {
  let data = try encoder.encode(value)
  if let path {
    try data.write(to: URL(fileURLWithPath: path))
  } else {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

func decode<T: Decodable>(_ type: T.Type, at path: String) throws -> T {
  try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

struct EvaluationReport: Encodable {
  var variant: String
  var pacing: String
  var timing: String
  var audioSeconds: Double
  var resultCount: Int
  var finalCount: Int
  /// Finalized transcript against the words the take actually spoke (script and ad-libs).
  var finalWordErrorRate: Double
  var latency: LatencySummary?
  var evaluation: Evaluation
}

struct LatencySummary: Encodable {
  /// Arrival minus the result's reported audio range end (real-time paced replay only).
  var volatileP50: Double
  var volatileP95: Double
  var finalP50: Double
  var finalP95: Double
  /// Per finalized word: first arrival of a result showing it minus the word's
  /// recognizer-reported end. Approximate pairing by range start and word index.
  var wordVisibleP50: Double
  var wordVisibleP95: Double
  var wordFinalP50: Double
  var wordFinalP95: Double
  /// Display reaching each sentence's last token minus that sentence's exact audio end.
  var followSentenceEndP50: Double
  var followSentenceEndP95: Double
  var followSentenceEndMissing: Int
}

func wordLatencies(_ trace: TranscriptionTrace) -> (visible: [Double], final: [Double]) {
  var visible: [Double] = []
  var final: [Double] = []
  for result in trace.results where result.isFinal {
    let candidates = trace.results.filter {
      $0.arrival <= result.arrival && abs($0.rangeStart - result.rangeStart) <= 0.5
    }
    for (index, word) in result.words.enumerated() {
      let text = Tokenizer.normalize(word.text)
      let first = candidates.first {
        $0.words.count > index
          && WordMatch.score(Tokenizer.normalize($0.words[index].text), text) > 0
      }
      visible.append((first ?? result).arrival - word.end)
      final.append(result.arrival - word.end)
    }
  }
  return (visible, final)
}

func percentile(_ values: [Double], _ p: Double) -> Double {
  let sorted = values.sorted()
  guard !sorted.isEmpty else { return .nan }
  return sorted[min(sorted.count - 1, Int((p * Double(sorted.count - 1)).rounded()))]
}

let script = ScriptIndex(text: DemoScript.text)
let args = Array(CommandLine.arguments.dropFirst())

do {
  switch args.first {
  case "probe":
    try emit(await Probe.capabilities(locale: option("--locale", in: args) ?? "en_US"), to: nil)
  case "make-fixtures":
    let directory = URL(fileURLWithPath: try required("--out", in: args), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let only = option("--only", in: args)
    for variant in FixtureMaker.variants where only == nil || only == variant.name {
      let manifest = try FixtureMaker.make(variant: variant, script: script, directory: directory)
      try emit(manifest, to: directory.appendingPathComponent("\(variant.name).json").path)
      print(
        "\(variant.name): \(String(format: "%.2f", manifest.durationSeconds)) s, \(manifest.segments.count) segments"
      )
    }
  case "transcribe":
    let pacing = Pacing(rawValue: option("--pacing", in: args) ?? "offline") ?? .offline
    let trace = try await FileTranscriber.transcribe(
      audio: URL(fileURLWithPath: try required("--audio", in: args)),
      locale: option("--locale", in: args) ?? "en_US",
      pacing: pacing, fastResults: args.contains("--fast"))
    try emit(trace, to: try required("--out", in: args))
    print(
      "\(trace.audioFile) \(pacing.rawValue): \(trace.results.count) results, audio \(String(format: "%.2f", trace.audioSeconds)) s, "
        + "wall \(String(format: "%.2f", trace.analysisWallSeconds)) s, prepare \(String(format: "%.2f", trace.prepareSeconds)) s, "
        + "cpu \(String(format: "%.2f", trace.cpuSeconds)) s, maxRSS \(trace.maxResidentBytes / 1_048_576) MiB"
    )
  case "evaluate":
    let trace = try decode(TranscriptionTrace.self, at: try required("--trace", in: args))
    let manifest = try decode(FixtureManifest.self, at: try required("--manifest", in: args))
    let truth = GroundTruth(script: script, segments: manifest.segments)
    let events = trace.events()
    let duration = max(manifest.durationSeconds, (events.map(\.availableAt).max() ?? 0)) + 1
    let result = Replay.run(script: script, events: events, duration: duration)
    let evaluation = Evaluator.evaluate(result, truth: truth)
    var latency: LatencySummary?
    if trace.pacing == .realtime {
      let volatile = trace.results.filter { !$0.isFinal }.map { $0.arrival - $0.rangeEnd }
      let final = trace.results.filter(\.isFinal).map { $0.arrival - $0.rangeEnd }
      let words = wordLatencies(trace)
      let follow = evaluation.segmentEndLatencies.compactMap { $0 }
      latency = LatencySummary(
        volatileP50: percentile(volatile, 0.5), volatileP95: percentile(volatile, 0.95),
        finalP50: percentile(final, 0.5), finalP95: percentile(final, 0.95),
        wordVisibleP50: percentile(words.visible, 0.5),
        wordVisibleP95: percentile(words.visible, 0.95),
        wordFinalP50: percentile(words.final, 0.5), wordFinalP95: percentile(words.final, 0.95),
        followSentenceEndP50: percentile(follow, 0.5),
        followSentenceEndP95: percentile(follow, 0.95),
        followSentenceEndMissing: evaluation.segmentEndLatencies.count - follow.count)
    }
    let report = EvaluationReport(
      variant: manifest.variant, pacing: trace.pacing.rawValue,
      timing: trace.pacing == .realtime
        ? "measured arrival" : "idealized: finals only, available at result audio end",
      audioSeconds: trace.audioSeconds, resultCount: trace.results.count,
      finalCount: trace.results.filter(\.isFinal).count,
      finalWordErrorRate: Evaluator.wordErrorRate(
        reference: Evaluator.spokenWords(truth),
        hypothesis: trace.results.filter(\.isFinal).flatMap(\.words).map {
          Tokenizer.normalize($0.text)
        }
        .filter { !$0.isEmpty }),
      latency: latency,
      evaluation: evaluation)
    try emit(report, to: option("--out", in: args))
  case "synthetic":
    func range(_ p: Int) -> Range<Int> {
      let indices = script.paragraphOfToken.indices.filter { script.paragraphOfToken[$0] == p }
      return indices.first!..<(indices.last! + 1)
    }
    let scenarios: [(String, [ReadingStep])] = [
      ("verbatim", [.read(0..<script.count)]),
      ("silence", [.read(range(0)), .silence(5), .read(range(1))]),
      ("skip", [.read(range(0)), .read(range(2))]),
      ("reread", [.read(range(0)), .read(range(1)), .read(range(1))]),
      (
        "adlib",
        [
          .read(range(0)), .adlib("and then she said the light and the lens were fine"),
          .read(range(1)),
        ]
      ),
    ]
    var reports: [String: Evaluation] = [:]
    for (name, steps) in scenarios {
      let take = Synthesizer.take(script: script, steps: steps)
      let result = Replay.run(script: script, events: take.events, duration: take.duration)
      reports[name] = Evaluator.evaluate(
        result, truth: GroundTruth(script: script, segments: take.truth))
    }
    try emit(reports, to: nil)
  default:
    throw UsageError(description: usage)
  }
} catch {
  FileHandle.standardError.write(Data("voicefollow: \(error)\n".utf8))
  exit(1)
}
