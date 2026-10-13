// swift-tools-version: 5.9
import PackageDescription
import Foundation

// JPEG XL writing is enabled only when libjxl has been built (see
// scripts/build-jxl.sh). Without it, JPEG XL is simply not an output target and
// its tests skip — a fresh clone still builds and tests cleanly.
let jxlLibPath = "ThirdParty/jxl-lib/fat"
let jxlHeaders = "ThirdParty/jxl-src/lib/include"
let hasJXL = FileManager.default.fileExists(atPath: jxlLibPath)
    && FileManager.default.fileExists(atPath: jxlHeaders)

// AVIF writing is enabled only when libavif (plus its aom encoder and libyuv)
// has been built (see scripts/build-avif.sh). Without it, AVIF is simply not an
// output target and its tests skip — a fresh clone still builds and tests
// cleanly.
let avifLibPath = "ThirdParty/avif-lib/fat"
let avifHeaders = "ThirdParty/avif-lib/include/avif/avif.h"
let hasAVIF = FileManager.default.fileExists(atPath: avifLibPath)
    && FileManager.default.fileExists(atPath: avifHeaders)

var coreDependencies: [Target.Dependency] = ["CWebP"]
var coreSwiftSettings: [SwiftSetting] = [.enableUpcomingFeature("ExistentialAny")]

var targets: [Target] = [
    .target(
        name: "CWebP",
        path: "ThirdParty/libwebp-c",
        publicHeadersPath: "src/webp",
        cSettings: [
            .headerSearchPath("."),
            .headerSearchPath("src"),
            .headerSearchPath("sharpyuv"),
        ]
    ),
]

if hasJXL {
    let absLib = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(jxlLibPath).path
    targets.append(.target(
        name: "CJXL",
        path: "ThirdParty/jxl-shim",
        publicHeadersPath: ".",
        cSettings: [
            .headerSearchPath("../jxl-src/lib/include"),
            .headerSearchPath("../jxl-lib/include"),
            .unsafeFlags(["-Wno-deprecated-declarations"]),
        ],
        linkerSettings: [
            .unsafeFlags([
                "-L\(absLib)",
                "-ljxl", "-ljxl_threads", "-ljxl_cms",
                "-lhwy", "-lbrotlienc", "-lbrotlidec", "-lbrotlicommon",
                "-llcms2", "-lz",
                "-lc++", "-lpthread", "-lm",
            ]),
        ]
    ))
    coreDependencies.append("CJXL")
    coreSwiftSettings.append(.define("CONV3RT_JXL"))
}

if hasAVIF {
    let absLib = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(avifLibPath).path
    targets.append(.target(
        name: "CAVIF",
        path: "ThirdParty/avif-shim",
        publicHeadersPath: ".",
        cSettings: [
            .headerSearchPath("../avif-lib/include"),
            .unsafeFlags(["-Wno-deprecated-declarations"]),
        ],
        linkerSettings: [
            .unsafeFlags([
                "-L\(absLib)",
                "-lavif", "-laom", "-lyuv",
                "-lc++", "-lpthread", "-lm",
            ]),
        ]
    ))
    coreDependencies.append("CAVIF")
    coreSwiftSettings.append(.define("CONV3RT_AVIF"))
}

targets.append(contentsOf: [
    .target(
        name: "Conv3rtCore",
        dependencies: coreDependencies,
        swiftSettings: coreSwiftSettings
    ),
    .executableTarget(
        name: "Conv3rtApp",
        dependencies: ["Conv3rtCore"]
    ),
    .testTarget(
        name: "Conv3rtCoreTests",
        dependencies: ["Conv3rtCore"],
        swiftSettings: (hasJXL ? [.define("CONV3RT_JXL")] : [])
            + (hasAVIF ? [.define("CONV3RT_AVIF")] : [])
    ),
])

let package = Package(
    name: "conv3rt",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Conv3rtCore", targets: ["Conv3rtCore"]),
        .executable(name: "conv3rt", targets: ["Conv3rtApp"]),
    ],
    targets: targets
)
