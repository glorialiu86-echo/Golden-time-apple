// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoldenTimeApple",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "GoldenTimeCore",
            targets: ["GoldenTimeCore"]
        ),
    ],
    targets: [
        .target(
            name: "GoldenTimeCore"
        ),
        .testTarget(
            name: "GoldenTimeCoreTests",
            dependencies: ["GoldenTimeCore"]
        ),
    ]
)
