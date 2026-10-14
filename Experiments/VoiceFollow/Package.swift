// swift-tools-version: 6.2
import PackageDescription

// Standalone experiment. macOS 26 applies only here; the CueGlass app keeps its own target.
let package = Package(
  name: "VoiceFollow", platforms: [.macOS(.v26)],
  products: [.executable(name: "voicefollow", targets: ["voicefollow"])],
  targets: [
    .target(name: "VoiceFollowCore"),
    .target(name: "VoiceFollowSpeech", dependencies: ["VoiceFollowCore"]),
    .executableTarget(name: "voicefollow", dependencies: ["VoiceFollowCore", "VoiceFollowSpeech"]),
    .testTarget(name: "VoiceFollowCoreTests", dependencies: ["VoiceFollowCore"]),
  ])
