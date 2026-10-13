import Foundation
import Testing

@testable import CueFlowCore

@Test(arguments: [1.0, 40, 300]) func timelinePositions(_ speed: Double) throws {
  var t = PlaybackTimeline()
  try t.setVelocity(speed, at: 0)
  try t.play(at: 0)
  for time in [0.5, 10, 3600] { #expect(abs(try t.position(at: time) - speed * time) < 1e-8) }
  let copy = t
  for n in 0...600 {
    let time = Double(n) / 60
    #expect(try t.position(at: time) == t.position(at: Double(n * 2) / 120))
  }
  #expect(t == copy)
}
@Test func transportContinuity() throws {
  var t = PlaybackTimeline()
  try t.play(at: 0)
  try t.setVelocity(80, at: 1)
  #expect(try t.position(at: 1) == 40)
  try t.pause(at: 2)
  #expect(try t.position(at: 32) == 120)
  try t.play(at: 32)
  #expect(try t.position(at: 33) == 200)
  let effective = StallPolicy.effectiveTime(now: 33, presented: 33.01)
  let last = try t.position(at: effective)
  try t.setVelocity(1, at: effective)
  #expect(try t.position(at: effective) == last)
  #expect(StallPolicy.shouldPause(previous: 0, target: 0.6))
  #expect(!StallPolicy.shouldPause(previous: 0, target: 0.4))
}
@Test func invalidTimelineDoesNotMutate() throws {
  var t = PlaybackTimeline()
  let copy = t
  for speed in [Double.nan, .infinity, 0, 301] {
    #expect(throws: TimelineError.self) { try t.setVelocity(speed, at: 0) }
    #expect(t == copy)
  }
  for time in [-1.0, .nan, .infinity] {
    #expect(throws: TimelineError.self) { try t.play(at: time) }
    #expect(t == copy)
  }
  #expect(throws: TimelineError.self) { try t.seek(to: -1, at: 0) }
}
@Test func codecRoundTripAndGuards() throws {
  let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
  var model = ScriptDocumentModel(documentID: id, title: "Test", rtf: Data("{\\rtf1 sample}".utf8))
  #expect(try ScriptFileCodec.decode(ScriptFileCodec.encode(model)).model == model)
  model.readingStyle.fontSize = 999
  let encoded = try JSONEncoder().encode(model)
  let decoded = try ScriptFileCodec.decode(encoded)
  #expect(decoded.model.readingStyle.fontSize == 180)
  #expect(decoded.adjustedFields.contains("font size"))
  model.formatVersion = 2
  #expect(throws: ScriptFileError.futureVersion(2)) {
    try ScriptFileCodec.decode(JSONEncoder().encode(model))
  }
  #expect(throws: (any Error).self) { try ScriptFileCodec.decode(Data("bad".utf8)) }
  #expect(throws: ScriptFileError.tooLarge) {
    try ScriptFileCodec.decode(Data(repeating: 0, count: ScriptFileCodec.maximumBytes + 1))
  }
  model.formatVersion = 1
  model.readingStyle.fontSize = .infinity
  #expect(throws: ScriptFileError.self) { try ScriptFileCodec.encode(model) }
  model.readingStyle.fontSize = 64
  model.content.format = "html"
  #expect(throws: ScriptFileError.invalidPayload) { try ScriptFileCodec.encode(model) }
}
@Test func unicodeAndEncoding() throws {
  let sample = "Привет 👩‍💻 é שלום\r\n\r\nEnd\r"
  let expected = "Привет 👩‍💻 é שלום\n\nEnd\n"
  #expect(try TextDecoding.decode(Data(sample.utf8)) == expected)
  #expect(try TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data(sample.utf8)) == expected)
  for (bom, encoding) in [
    ([UInt8](arrayLiteral: 0xFF, 0xFE), String.Encoding.utf16LittleEndian),
    ([0xFE, 0xFF], .utf16BigEndian),
  ] {
    #expect(try TextDecoding.decode(Data(bom) + sample.data(using: encoding)!) == expected)
  }
  #expect(throws: TextDecodingError.self) { try TextDecoding.decode(Data([0xFF, 0x80])) }
  #expect(try TextDecoding.decode(Data([0xE9]), choice: .windowsCP1252) == "é")
  #expect(try TextDecoding.decode(Data()) == "")
}
@Test func anchorsAndReflections() {
  let text = "A👩‍💻éB"
  #expect(GraphemeBoundary.alignDown(3, in: text) == 1)
  #expect(GraphemeBoundary.alignDown(7, in: text) == 6)
  #expect(GraphemeBoundary.alignDown(100, in: text) == 9)
  #expect(AnchorCarryOver.offset(old: text, new: "changed", offset: 6) == 0)
  for h in [false, true] {
    for v in [false, true] {
      let a = Affine2D.reflection(width: 100, height: 50, horizontal: h, vertical: v)
      let p = a.map(x: 10, y: 20)
      #expect(p.0 == (h ? 90 : 10))
      #expect(p.1 == (v ? 30 : 20))
    }
  }
}
@Test func cloudAndDisplayDecisions() {
  #expect(CloudStatus.map(.init()) == .local)
  #expect(CloudStatus.map(.init(ubiquitous: true, downloaded: false)) == .notDownloaded)
  #expect(CloudStatus.map(.init(ubiquitous: true, downloading: true)) == .downloading)
  #expect(CloudStatus.map(.init(ubiquitous: true, uploading: true)) == .uploading)
  #expect(CloudStatus.map(.init(ubiquitous: true, uploaded: true)) == .uploadedToICloud)
  #expect(CloudStatus.map(.init(conflict: true)) == .conflict)
  #expect(CloudStatus.map(.init(error: true)) == .error)
  #expect(CloudStatus.map(.init(ubiquitous: true)) == .unknown)
  let a = DisplayPreference(uuid: "a", name: "Screen")
  let b = DisplayPreference(uuid: "b", name: "Screen")
  #expect(DisplayMatcher.match(a, in: [b, a]) == 1)
  #expect(DisplayMatcher.match(.init(uuid: nil, name: "Screen"), in: [a, b]) == nil)
  #expect(DisplayMatcher.match(.init(uuid: nil, name: "Screen"), in: [a]) == 0)
}

@Test func optionalDefaultsAndStyleValidation() throws {
  let data = Data(
    "{\"formatVersion\":1,\"documentID\":\"11111111-2222-3333-4444-555555555555\",\"content\":{\"format\":\"rtf\",\"data\":\"e1xydGYxIH0=\"}}"
      .utf8)
  let decoded = try ScriptFileCodec.decode(data)
  #expect(decoded.model.readingStyle.fontSize == 64)
  #expect(decoded.model.preferredSpeedPointsPerSecond == 40)
  var style = ReadingStyle()
  style.columnWidthFraction = -10
  style.readingGuideFraction = 100
  let valid = try ScriptFileCodec.validatedStyle(style)
  #expect(valid.columnWidthFraction == 0.25)
  #expect(valid.readingGuideFraction == 1)
  style.fontSize = .nan
  #expect(throws: ScriptFileError.self) { try ScriptFileCodec.validatedStyle(style) }
  style = ReadingStyle()
  style.backgroundRGBA = [1, 2]
  #expect(throws: ScriptFileError.self) { try ScriptFileCodec.validatedStyle(style) }
}

@Test func rejectsBooleanVersionAndOverflow() throws {
  #expect(throws: ScriptFileError.malformed) {
    try ScriptFileCodec.decode(Data("{\"formatVersion\":true}".utf8))
  }
  var timeline = PlaybackTimeline()
  try timeline.play(at: 0)
  #expect(throws: TimelineError.invalidPosition) {
    try timeline.position(at: .greatestFiniteMagnitude)
  }
}
