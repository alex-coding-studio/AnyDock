// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnyDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AnyDock", targets: ["AnyDock"])],
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit", exact: "6.0.0"),
        .package(
            url: "https://github.com/alex-coding-studio/PockyFoundation",
            .upToNextMinor(from: "0.9.0")
        ),
    ],
    targets: [
        .target(name: "AnyDockCore"),
        .executableTarget(
            name: "AnyDock",
            dependencies: [
                "AnyDockCore",
                .product(name: "SnapKit", package: "SnapKit"),
                .product(name: "PockyFoundation", package: "PockyFoundation"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AnyDockCoreTests", dependencies: ["AnyDockCore"]),
        .testTarget(
            name: "AnyDockTests",
            dependencies: [
                "AnyDock",
                "AnyDockCore",
                .product(name: "SnapKit", package: "SnapKit"),
            ]
        ),
    ]
)
