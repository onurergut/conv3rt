import XCTest
import ImageIO
@testable import Conv3rtCore

/// Regressions for the audit blockers: silent content loss must be blocked, and
/// "Lossless" must be verified, not assumed.
final class BlockerRegressionTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    // MARK: - Blocker 1: Lossless must not silently discard pages

    func testFirstPageOnlyIsBlockedInLosslessEvenWhenTargetCanHoldAllPages() throws {
        let dir = TempDir()
        let src = try Fixtures.multipageTIFF(directory: dir.url, pages: 3)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.pageCount, 3)

        // TIFF can hold all pages, but the user asked for the first only.
        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .firstOnly))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "frames.firstOnly" })
    }

    func testFirstPageOnlyAllowedInHighestQuality() throws {
        let dir = TempDir()
        let src = try Fixtures.multipageTIFF(directory: dir.url, pages: 3)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .highestQuality, framePolicy: .firstOnly))
        XCTAssertTrue(plan.isConvertible)
        XCTAssertTrue(plan.changes.contains { $0.code == "frames.firstOnly" })
    }

    // MARK: - Blocker 2: no false bit-depth claims

    func testSixteenBitToJXLLosslessIsBlocked() throws {
        #if CONV3RT_JXL
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.bitsPerComponent, 16)
        let plan = planner.plan(source: info, target: target("jxl"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "depth.reduced" },
                      "JPEG XL write path is 8-bit, so 16-bit lossless must be blocked")
        #endif
    }

    func testSixteenBitToPNGLosslessStillAllowed() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertNotEqual(plan.status, .blocked)
    }

    // MARK: - Blocker 3: Lossless is actually verified

    func testGIFLosslessWithTooManyColorsFailsVerification() throws {
        let dir = TempDir()
        // BMP carries no color profile, so GIF Lossless passes planning (with a
        // palette warning) and reaches conversion — where quantization loses
        // samples and the verifier must catch it.
        let src = try Fixtures.write(Fixtures.manyColors(width: 64, height: 64),
                                     uti: "com.microsoft.bmp", ext: "bmp",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        XCTAssertFalse(info.hasColorProfile)
        let plan = planner.plan(source: info, target: target("gif"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible, "planner warns but allows; verification must catch the loss")
        XCTAssertThrowsError(
            try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                           namer: OutputNamer(), target: target("gif"))
        ) { error in
            guard case ConversionError.verificationFailed = error else {
                return XCTFail("expected verification failure, got \(error)")
            }
        }
    }

    func testLosslessPNGtoPNGPassesVerification() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertNoThrow(try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                        namer: OutputNamer(), target: target("png")))
    }

    // MARK: - Blocker 5: cancellation writes nothing for a bundled codec

    func testCancelBeforeCustomCodecWriteLeavesNoOutput() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertThrowsError(
            try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                           namer: OutputNamer(), target: target("webp"),
                                           isCancelled: { true })
        ) { error in
            XCTAssertEqual(error as? ConversionError, .canceled)
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        XCTAssertFalse(remaining.contains { $0.hasSuffix(".webp") }, "no output after cancel")
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".conv3rt-") }, "no temp after cancel")
    }

    // MARK: - Blocker 6: AVIF must not claim metadata it does not write

    func testAVIFReportsLimitedMetadata() throws {
        let avif = target("avif")
        try XCTSkipUnless(avif.canWrite, "AVIF codec is not built in this environment")
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)   // has GPS + EXIF
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: avif,
                                settings: ConversionSettings(mode: .highestQuality, metadataPolicy: .keep))
        XCTAssertTrue(plan.changes.contains { $0.code == "meta.limited" },
                      "AVIF does not write EXIF/XMP, so metadata must be reported as limited")
        XCTAssertFalse(avif.supportsMetadata)
    }
}
