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
            name: "CWebP",
            path: "ThirdParty/libwebp-c",
            publicHeadersPath: "src/webp",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("src"),
                .headerSearchPath("sharpyuv"),
                .define("WEBP_USE_THREAD", to: "0"),
            ]
        ),
        .target(
            name: "Conv3rtCore",
            dependencies: ["CWebP"],
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
