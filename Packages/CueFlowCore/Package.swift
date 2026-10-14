// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CueFlowCore", platforms: [.macOS(.v14)],
  products: [.library(name: "CueFlowCore", targets: ["CueFlowCore"])],
  targets: [
    .target(name: "CueFlowCore"),
    .testTarget(name: "CueFlowCoreTests", dependencies: ["CueFlowCore"]),
  ])
