import Foundation

public enum PlaybackCommand: String, Codable, CaseIterable, Sendable {
  case toggle, faster, slower, jumpFaster, jumpSlower, nextParagraph, previousParagraph, restart,
    reverse, exit, cameraDock
}
public struct KeyChord: Codable, Hashable, Sendable {
  public var key: String
  public var shift: Bool, command: Bool, option: Bool, control: Bool
  public init(
    _ key: String, shift: Bool = false, command: Bool = false, option: Bool = false,
    control: Bool = false
  ) {
    self.key = key.lowercased()
    self.shift = shift
    self.command = command
    self.option = option
    self.control = control
  }
  public var label: String {
    (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key
  }
}
public enum BindingError: Error { case conflict, reserved, invalid }
public struct CommandMap: Codable, Sendable {
  public struct Binding: Codable, Sendable {
    public let chord: KeyChord
    public let command: PlaybackCommand
  }
  public var version = 1
  public private(set) var bindings: [Binding]
  public init() {
    bindings = [
      .init(chord: .init("space"), command: .toggle), .init(chord: .init("b"), command: .toggle),
      .init(chord: .init("."), command: .toggle), .init(chord: .init("up"), command: .faster),
      .init(chord: .init("down"), command: .slower),
      .init(chord: .init("up", shift: true), command: .jumpFaster),
      .init(chord: .init("down", shift: true), command: .jumpSlower),
      .init(chord: .init("pagedown"), command: .nextParagraph),
      .init(chord: .init("right"), command: .nextParagraph),
      .init(chord: .init("pageup"), command: .previousParagraph),
      .init(chord: .init("left"), command: .previousParagraph),
      .init(chord: .init("home"), command: .restart),
      .init(chord: .init("up", command: true), command: .restart),
      .init(chord: .init("r"), command: .reverse), .init(chord: .init("escape"), command: .exit),
      .init(chord: .init("d", command: true, option: true), command: .cameraDock),
    ]
  }
  public func command(for chord: KeyChord) -> PlaybackCommand? {
    bindings.first { $0.chord == chord }?.command
  }
  public mutating func bind(_ chord: KeyChord, to command: PlaybackCommand) throws {
    guard !(chord.key == "escape" && command != .exit) else { throw BindingError.reserved }
    guard !chord.key.isEmpty, chord.key.count <= 32 else { throw BindingError.invalid }
    guard
      !(chord.command
        && ["q", "w", "s", "o", "n", "z", "x", "c", "v", "a", "p", "h", "m", ","].contains(
          chord.key))
    else { throw BindingError.reserved }
    guard !bindings.contains(where: { $0.chord == chord && $0.command != command }) else {
      throw BindingError.conflict
    }
    bindings.removeAll { $0.command == command }
    bindings.append(.init(chord: chord, command: command))
  }
  public static func decode(_ data: Data) throws -> Self {
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == 1 else { throw BindingError.invalid }
    var seen: Set<KeyChord> = []
    for binding in value.bindings {
      guard seen.insert(binding.chord).inserted else { throw BindingError.conflict }
      var test = CommandMap()
      test.bindings = []
      try test.bind(binding.chord, to: binding.command)
    }
    return value
  }
}
