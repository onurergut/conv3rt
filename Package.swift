// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "conv3rt",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Conv3rtCore", targets: ["Conv3rtCore"]),
        .executable(name: "conv3rt", targets: ["Conv3rtApp"]),
    ],
    targets: [
        .target(
            name: "Conv3rtCore",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .executableTarget(
            name: "Conv3rtApp",
            dependencies: ["Conv3rtCore"]
        ),
        .testTarget(
            name: "Conv3rtCoreTests",
            dependencies: ["Conv3rtCore"]
        ),
    ]
)
