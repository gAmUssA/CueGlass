import Foundation
import Testing

@testable import CueFlowCore

@Test func speedAndReverseContracts() throws {
  let pace = try SpeedModel(lpm: 30, lineAdvance: 100)
  #expect(pace.pointsPerSecond == 50)
  #expect(try SpeedModel(lpm: 30, lineAdvance: 200).pointsPerSecond == 100)
  #expect(try SpeedModel(lpm: 240, lineAdvance: 424).pointsPerSecond == 1696)
  #expect(try SpeedModel(lpm: 240, lineAdvance: 1216).limitedByLayout)
  #expect(try SpeedModel(lpm: 1, lineAdvance: 100).nominalLPM == 2)
  #expect(try SpeedModel(lpm: 300, lineAdvance: 100, configuredMax: 90).nominalLPM == 90)
  #expect(throws: TimelineError.self) { try SpeedModel(lpm: .nan, lineAdvance: 100) }
  var t = PlaybackTimeline()
  try t.setVelocity(50, at: 0)
  try t.setUpperBound(200, at: 0)
  try t.seek(to: 100, at: 0)
  try t.setDirection(.reverse, at: 0)
  try t.play(at: 0)
  #expect(try t.position(at: 1) == 50)
  #expect(try t.position(at: 3) == 0)
  #expect(try t.boundReached(at: 3))
  try t.setDirection(.forward, at: 1)
  #expect(try t.position(at: 1) == 50)
  #expect(try t.position(at: 5) == 200)
  let copy = t
  for n in 0...120 {
    #expect(try t.position(at: 1 + Double(n) / 60) == t.position(at: 1 + Double(n * 2) / 120))
  }
  #expect(t == copy)
}
@Test func navigationAndScrub() {
  #expect(ParagraphIndex.starts(in: "one\n \n👩‍💻two\nthree") == [0, 6, 15])
  #expect(
    ParagraphIndex.target(
      position: 150, starts: [0, 100, 200], forward: false, lineAdvance: 40, end: 300) == 100)
  #expect(
    ParagraphIndex.target(
      position: 105, starts: [0, 100, 200], forward: false, lineAdvance: 40, end: 300) == 0)
  #expect(
    ParagraphIndex.target(
      position: 105, starts: [0, 100, 200], forward: true, lineAdvance: 40, end: 300) == 200)
  var gate = ScrubGate()
  let a = gate.accepts(momentum: true)
  let b = gate.accepts(momentum: false)
  let c = gate.accepts(momentum: true)
  gate.play()
  let d = gate.accepts(momentum: true)
  #expect(!a)
  #expect(b)
  #expect(c)
  #expect(!d)
  #expect(
    ScrubGate.delta(rawY: 2, precise: true, lineAdvance: 10, scale: 0.5, verticalReflection: false)
      == (-4))
  #expect(
    ScrubGate.delta(rawY: 2, precise: false, lineAdvance: 10, scale: 0.5, verticalReflection: false)
      == (-40))
  #expect(
    ScrubGate.delta(rawY: 2, precise: true, lineAdvance: 10, scale: 0.5, verticalReflection: true)
      == 4)
}
@Test func timingAndCommandPersistence() throws {
  #expect(
    try TimedScrollSolver.solve(
      position: 0, end: 15000, seconds: 300, lineAdvance: 100, maximum: 240) == 30)
  #expect(throws: TimedScrollError.tooFast(300, 240)) {
    try TimedScrollSolver.solve(
      position: 0, end: 150000, seconds: 300, lineAdvance: 100, maximum: 240)
  }
  #expect(throws: TimedScrollError.self) {
    try TimedScrollSolver.solve(position: 0, end: nil, seconds: 300, lineAdvance: 100, maximum: 240)
  }
  #expect(throws: TimedScrollError.self) {
    try TimedScrollSolver.solve(position: 0, end: 10, seconds: .nan, lineAdvance: 100, maximum: 240)
  }
  #expect(throws: TimedScrollError.unrepresentable) {
    try TimedScrollSolver.solve(
      position: -.greatestFiniteMagnitude, end: .greatestFiniteMagnitude, seconds: 300,
      lineAdvance: 100, maximum: 240)
  }
  #expect(
    TimedScrollError.tooFast(.greatestFiniteMagnitude, 240).errorDescription != nil)
  #expect(TimedScrollError.tooFast(.infinity, 240).errorDescription != nil)
  var elapsed = ElapsedClock()
  elapsed.play(at: 0)
  elapsed.pause(at: 5)
  elapsed.play(at: 30)
  #expect(elapsed.value(at: 32) == 7)
  var map = CommandMap()
  #expect(map.command(for: .init("b")) == .toggle)
  #expect(map.command(for: .init("up", shift: true)) == .jumpFaster)
  #expect(throws: BindingError.self) { try map.bind(.init("q", command: true), to: .reverse) }
  #expect(throws: BindingError.self) { try map.bind(.init("b"), to: .reverse) }
  try map.bind(.init("f"), to: .reverse)
  #expect(try CommandMap.decode(JSONEncoder().encode(map)).command(for: .init("f")) == .reverse)
  let frame = FrameClamp.clamp(
    FrameClamp.Rect(x: -3000, y: 500, width: 3000, height: 2000),
    to: FrameClamp.Rect(x: -1920, y: 0, width: 1920, height: 1080))
  #expect(frame == FrameClamp.Rect(x: -1920, y: 0, width: 1920, height: 1080))
  #expect(
    Contrast.worst(
      text: [0.949, 0.949, 0.933], background: [0.039, 0.039, 0.043], windowAlpha: 0.85,
      panelAlpha: 1) > 4.5)
  #expect(
    Contrast.worst(
      text: [0.949, 0.949, 0.933], background: [0.039, 0.039, 0.043], windowAlpha: 0.3,
      panelAlpha: 1) < 4.5)
}
@Test func expandedSchemaDefaultsAndDiagnostics() throws {
  var model = ScriptDocumentModel(
    documentID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
    rtf: Data("{\\rtf1 }".utf8))
  model.readingStyle.fontWeight = .bold
  model.readingStyle.systemDesign = .serif
  model.readingStyle.readingGuideStyle = .triangle
  model.readingStyle.edgeFadeFraction = 0.2
  let encoded = try ScriptFileCodec.encode(model)
  #expect(try ScriptFileCodec.decode(encoded).model == model)
  var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  var style = try #require(json["readingStyle"] as? [String: Any])
  style["fontWeight"] = "future"
  style["readingGuideStyle"] = "future"
  style["edgeFadeFraction"] = 0.4
  json["readingStyle"] = style
  json.removeValue(forKey: "preferredSpeedLinesPerMinute")
  json["preferredSpeedPointsPerSecond"] = 300
  let decoded = try ScriptFileCodec.decode(JSONSerialization.data(withJSONObject: json))
  #expect(decoded.model.preferredSpeedLinesPerMinute == 30)
  #expect(decoded.model.readingStyle.fontWeight == .medium)
  #expect(decoded.adjustedFields.contains("fontWeight"))
  #expect(decoded.model.readingStyle.edgeFadeFraction == 0.3)
  #expect(
    !String(decoding: try ScriptFileCodec.encode(decoded.model), as: UTF8.self).contains(
      "preferredSpeedPointsPerSecond"))
}

@Test func transparentInkWarns() {
  #expect(
    Contrast.worst(text: [1, 1, 1, 0], background: [0, 0, 0, 1], windowAlpha: 1, panelAlpha: 1) == 1
  )
}
