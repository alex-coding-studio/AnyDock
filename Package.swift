// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SnapDock",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "SnapDock", targets: ["SnapDock"])],
  targets: [
    .target(name: "SnapDockCore"),
    .executableTarget(
      name: "SnapDock", dependencies: ["SnapDockCore"], resources: [.process("Resources")]),
    .testTarget(name: "SnapDockCoreTests", dependencies: ["SnapDockCore"]),
  ]
)
