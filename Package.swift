// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnyDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AnyDock", targets: ["AnyDock"])],
    dependencies: [
        .package(
            url: "https://github.com/alex-coding-studio/PockyFoundation",
            .upToNextMinor(from: "0.1.0")
        ),
    ],
    targets: [
        .target(name: "AnyDockCore"),
        .executableTarget(
            name: "AnyDock",
            dependencies: [
                "AnyDockCore",
                .product(name: "PockyFoundation", package: "PockyFoundation"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AnyDockCoreTests", dependencies: ["AnyDockCore"]),
        .testTarget(name: "AnyDockTests", dependencies: ["AnyDock", "AnyDockCore"]),
    ]
)
