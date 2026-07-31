// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bessie",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BessieCore", targets: ["BessieCore"]),
        .executable(name: "BessieApp", targets: ["BessieApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Lakr233/libghostty-spm.git",
            exact: "1.3.2"
        ),
    ],
    targets: [
        .target(name: "BessieCore"),
        .executableTarget(
            name: "BessieApp",
            dependencies: [
                "BessieCore",
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BessieCoreTests",
            dependencies: ["BessieCore"]
        ),
        .testTarget(
            name: "BessieAppModelTests",
            dependencies: ["BessieCore"]
        ),
    ]
)
