// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AnyDock",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "AnyDock", targets: ["AnyDock"])],
  targets: [
    .target(name: "AnyDockCore"),
    .executableTarget(
      name: "AnyDock", dependencies: ["AnyDockCore"], resources: [.process("Resources")]),
    .testTarget(name: "AnyDockCoreTests", dependencies: ["AnyDockCore"]),
  ]
)
