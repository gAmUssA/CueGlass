import Foundation

// Swift 6+, Foundation only. Generated binary/large fixtures remain ignored.
let root = URL(
  fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let sample = "Привет 👩‍💻 é שלום\r\n\r\nEnd\r"
for (name, bom, encoding) in [
  ("utf16le.txt", [UInt8](arrayLiteral: 0xFF, 0xFE), String.Encoding.utf16LittleEndian),
  ("utf16be.txt", [0xFE, 0xFF], .utf16BigEndian),
] {
  guard let data = sample.data(using: encoding) else {
    fatalError("Synthetic fixture cannot be encoded")
  }
  try (Data(bom) + data).write(to: root.appendingPathComponent(name))
}
try Data([0xFF, 0x80]).write(to: root.appendingPathComponent("invalid-utf8.txt"))
let large = (0..<10000).map { "Line \($0): one two three four five six seven eight" }.joined(
  separator: "\n")
try Data(large.utf8).write(to: root.appendingPathComponent("100000-words.txt"))
print("Generated UTF-16, invalid UTF-8, and 100,000-word fixtures in \(root.lastPathComponent)")
