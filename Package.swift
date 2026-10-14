// swift-tools-version: 5.9
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let jxlLibPath = packageRoot.appendingPathComponent("ThirdParty/jxl-lib/fat").path
let avifLibPath = packageRoot.appendingPathComponent("ThirdParty/avif-lib/fat").path
let hasJXL = FileManager.default.fileExists(atPath: "\(jxlLibPath)/libjxl.a")
    && FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("ThirdParty/jxl-lib/include/jxl/encode.h").path)
    && FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("ThirdParty/jxl-lib/include/jxl/jxl_export.h").path)
let hasAVIF = FileManager.default.fileExists(atPath: "\(avifLibPath)/libavif.a")
    && FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("ThirdParty/avif-lib/include/avif/avif.h").path)

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
    targets.append(.target(
        name: "CJXL",
        path: "ThirdParty/jxl-shim",
        publicHeadersPath: ".",
        cSettings: [
            .headerSearchPath("../jxl-lib/include"),
            .unsafeFlags(["-Wno-deprecated-declarations"]),
        ],
        linkerSettings: [
            .unsafeFlags([
                "-L\(jxlLibPath)",
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
                "-L\(avifLibPath)",
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
        dependencies: ["Conv3rtCore", .product(name: "Sparkle", package: "Sparkle")],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .testTarget(
        name: "Conv3rtAppTests",
        dependencies: ["Conv3rtApp"]
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
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: targets
)
