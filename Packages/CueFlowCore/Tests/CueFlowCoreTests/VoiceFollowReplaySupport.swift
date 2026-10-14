import CueFlowCore
import Foundation

public struct TimedCommand: Sendable {
  public var time: Double
  public var command: ManualCommand

  public init(time: Double, command: ManualCommand) {
    self.time = time
    self.command = command
  }
}

public struct ReplaySample: Sendable, Codable, Equatable {
  public var time: Double
  public var display: Double
  public var confidence: FollowConfidence
  public var suspended: Bool
  public var mode: PlaybackMode
}

public struct DecisionRecord: Sendable, Equatable {
  public var time: Double
  public var decision: FollowDecision
}

public struct ReplayResult: Sendable {
  public var samples: [ReplaySample]
  public var decisions: [DecisionRecord]
  public var revisions: Int
  public var manualTimes: [Double]
}

/// Deterministic replay on an injected audio clock with a fixed step. Events are delivered
/// when `availableAt` is reached; nothing reads the wall clock.
public enum Replay {
  public static func run(
    script: ScriptIndex, events: [TranscriptEvent], commands: [TimedCommand] = [],
    duration: Double, step: Double = 0.05, config: FollowConfig = FollowConfig()
  ) -> ReplayResult {
    let ordered = events.enumerated().sorted {
      ($0.element.availableAt, $0.offset) < ($1.element.availableAt, $1.offset)
    }.map(\.element)
    let manual = commands.sorted { $0.time < $1.time }
    var controller = FollowController(policy: FollowPolicy(script: script, config: config))
    var accumulator = TranscriptAccumulator()
    var nextEvent = 0
    var nextCommand = 0
    var samples: [ReplaySample] = []
    var decisions: [DecisionRecord] = []
    let steps = Int((duration / step).rounded(.up))
    for k in 0...steps {
      let now = Double(k) * step
      while nextCommand < manual.count && manual[nextCommand].time <= now {
        controller.handle(manual[nextCommand].command, now: now)
        nextCommand += 1
      }
      while nextEvent < ordered.count && ordered[nextEvent].availableAt <= now {
        accumulator.apply(ordered[nextEvent])
        nextEvent += 1
        let decision = controller.ingest(hypothesis: accumulator.hypothesis)
        if decision != .none { decisions.append(DecisionRecord(time: now, decision: decision)) }
      }
      let tick = controller.tick(now: now, elapsed: k == 0 ? 0 : step)
      if tick != .none { decisions.append(DecisionRecord(time: now, decision: tick)) }
      samples.append(
        ReplaySample(
          time: now, display: controller.scroll.position, confidence: controller.policy.confidence,
          suspended: controller.policy.suspended, mode: controller.mode))
    }
    return ReplayResult(
      samples: samples, decisions: decisions, revisions: accumulator.revisions,
      manualTimes: manual.map(\.time))
  }
}
