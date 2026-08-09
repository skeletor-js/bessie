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
        .executable(name: "bessie", targets: ["BessieCLI"]),
        .executable(name: "bessie-mcp", targets: ["BessieMCP"]),
        .executable(name: "BessieMigrationTool", targets: ["BessieMigrationTool"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Lakr233/libghostty-spm.git",
            exact: "1.3.2"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.5"
        ),
    ],
    targets: [
        .target(name: "BessieCore"),
        .executableTarget(
            name: "BessieApp",
            dependencies: [
                "BessieCore",
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "BessieCLI",
            dependencies: ["BessieCore"]
        ),
        .executableTarget(
            name: "BessieMCP",
            dependencies: ["BessieCore"]
        ),
        .executableTarget(
            name: "BessieMigrationTool",
            dependencies: ["BessieCore"]
        ),
        .testTarget(
            name: "BessieCoreTests",
            dependencies: ["BessieCore"]
        ),
        .testTarget(
            name: "BessieAppModelTests",
            dependencies: [
                "BessieCore",
                "BessieApp",
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ]
        ),
        .testTarget(
            name: "BessieCLITests",
            dependencies: ["BessieCore", "BessieCLI"]
        ),
        .testTarget(
            name: "BessieMCPTests",
            dependencies: ["BessieCore", "BessieMCP"]
        ),
        .testTarget(
            name: "BessieMigrationToolTests",
            dependencies: ["BessieMigrationTool"]
        ),
    ]
)
