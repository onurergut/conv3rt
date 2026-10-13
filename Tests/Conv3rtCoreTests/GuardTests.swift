import XCTest
@testable import Conv3rtCore

/// Resource guards (decompression bombs, absurd/invalid dimensions), truncated
/// input handling, and CMYK color-model safety.
final class GuardTests: XCTestCase {

    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    private func makeInfo(width: Int, height: Int, bitsPerPixel: Int = 32,
                          frames: Int = 1, colorModel: String = "RGB") -> ImageInfo {
        ImageInfo(
            url: URL(fileURLWithPath: "/tmp/does-not-exist.png"),
            detectedUTI: "public.png", declaredUTI: "public.png", fileSize: 0,
            pixelWidth: width, pixelHeight: height, frameCount: frames, pageCount: 1,
            frameDurations: [], loopCount: nil, canvasWidth: width, canvasHeight: height,
            bitsPerComponent: 8, bitsPerPixel: bitsPerPixel, hasAlpha: true,
            colorModel: colorModel, colorSpaceName: "sRGB", hasColorProfile: true,
            exifOrientation: nil, hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false
        )
    }

    // MARK: - Resource guards

    func testInvalidDimensionsAreBlocked() {
        let planner = ConversionPlanner()
        let plan = planner.plan(source: makeInfo(width: 0, height: 10),
                                target: target("png"), settings: ConversionSettings(mode: .highestQuality))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "resource.invalid" })
    }

    func testOversizeImageIsBlockedNotDownscaled() {
        // 100k × 100k × 4 bytes ≈ 40 GB, well over the default 4 GiB limit.
        let planner = ConversionPlanner()
        let plan = planner.plan(source: makeInfo(width: 100_000, height: 100_000),
                                target: target("png"), settings: ConversionSettings(mode: .highestQuality))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "resource.tooLarge" })
    }

    func testManyFramesPushOverTheLimit() {
        // 2000 × 2000 × 4 × 200 frames ≈ 3.2 GB; a tight limit catches it.
        let planner = ConversionPlanner(resourceLimitBytes: 1_000_000)
        let plan = planner.plan(source: makeInfo(width: 2000, height: 2000, frames: 200),
                                target: target("png"), settings: ConversionSettings(mode: .highestQuality))
        XCTAssertEqual(plan.status, .blocked)
    }

    func testSaneImagePassesTheGuard() {
        let planner = ConversionPlanner()
        let plan = planner.plan(source: makeInfo(width: 800, height: 600),
                                target: target("png"), settings: ConversionSettings(mode: .lossless))
        XCTAssertNotEqual(plan.status, .blocked)
    }

    // MARK: - Corrupt / truncated input

    func testGarbageFileIsRejectedCleanly() throws {
        let dir = TempDir()
        let garbage = dir.url.appendingPathComponent("garbage.png")
        try Data((0..<128).map { _ in UInt8.random(in: 0...255) }).write(to: garbage)

        XCTAssertFalse(ImageInspector().isReadable(url: garbage))
        XCTAssertThrowsError(try ImageInspector().inspect(url: garbage))
    }

    func testTruncatedPNGFailsConversionWithoutLeavingOutput() throws {
        let dir = TempDir()
        let out = TempDir()
        let good = try Fixtures.write(Fixtures.manyColors(width: 64, height: 64),
                                      uti: "public.png", ext: "png", directory: dir.url, name: "src")
        let data = try Data(contentsOf: good)
        let truncated = dir.url.appendingPathComponent("truncated.png")
        try data.prefix(64).write(to: truncated)   // header only, no image data

        let info = try ImageInspector().inspect(url: truncated)
        let plan = ConversionPlanner().plan(source: info, target: target("png"),
                                            settings: ConversionSettings(mode: .highestQuality))
        XCTAssertThrowsError(
            try ConversionEngine().convert(plan: plan, outputDirectory: out.url,
                                           namer: OutputNamer(), target: target("png"))
        )
        let remaining = try FileManager.default.contentsOfDirectory(atPath: out.url.path)
        XCTAssertTrue(remaining.isEmpty, "A failed decode must not leave an output file")
    }

    // MARK: - CMYK

    func testCMYKSourceIsDetected() throws {
        let dir = TempDir()
        let cmyk = try Fixtures.cmykJpeg(directory: dir.url)
        let info = try ImageInspector().inspect(url: cmyk)
        XCTAssertEqual(info.colorModel, "CMYK")
    }

    func testCMYKtoRGBIsBlockedInLossless() throws {
        let dir = TempDir()
        let cmyk = try Fixtures.cmykJpeg(directory: dir.url)
        let info = try ImageInspector().inspect(url: cmyk)
        let plan = ConversionPlanner().plan(source: info, target: target("png"),
                                            settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "color.cmyk" })
    }

    func testCMYKtoRGBAllowedInHighestQualityWithWarning() throws {
        let dir = TempDir()
        let cmyk = try Fixtures.cmykJpeg(directory: dir.url)
        let info = try ImageInspector().inspect(url: cmyk)
        let plan = ConversionPlanner().plan(source: info, target: target("png"),
                                            settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isConvertible)
        XCTAssertTrue(plan.changes.contains { $0.code == "color.cmyk" })
    }

    func testCMYKtoTIFFDoesNotFlagColorConversion() throws {
        let dir = TempDir()
        let cmyk = try Fixtures.cmykJpeg(directory: dir.url)
        let info = try ImageInspector().inspect(url: cmyk)
        let plan = ConversionPlanner().plan(source: info, target: target("tiff"),
                                            settings: ConversionSettings(mode: .highestQuality))
        XCTAssertFalse(plan.changes.contains { $0.code == "color.cmyk" },
                       "TIFF can carry CMYK, so no color conversion is flagged")
    }
}
