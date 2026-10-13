import XCTest
import ImageIO
@testable import Conv3rtCore

final class ConversionTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared

    private func target(_ id: String) -> FormatCapability {
        guard let t = registry.capability(id: id) else {
            fatalError("missing target \(id)")
        }
        return t
    }

    // MARK: - Lossless roundtrips

    func testPNGtoPNGLosslessIsSampleIdentical() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .undecided))
        XCTAssertEqual(plan.status, .ready, "PNG→PNG should be lossless-ready")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)

        let a = try Fixtures.rgbaBytes(of: src)
        let b = try Fixtures.rgbaBytes(of: result.outputs[0])
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "PNG→PNG must not change any sample")
    }

    func testPNGtoTIFFLosslessIsSampleIdentical() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .ready)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("tiff"))
        let a = try Fixtures.rgbaBytes(of: src)
        let b = try Fixtures.rgbaBytes(of: result.outputs[0])
        XCTAssertEqual(a.bytes, b.bytes, "PNG→TIFF must not change any sample")
    }

    // MARK: - Adding no loss over an already-lossy source

    func testJPEGtoPNGAddsNoLossBeyondTheJPEGItself() throws {
        let dir = TempDir()
        // Source JPEG (lossy by nature).
        let jpeg = try Fixtures.write(Fixtures.manyColors(), uti: "public.jpeg", ext: "jpg",
                                      directory: dir.url, name: "src")
        let info = try inspector.inspect(url: jpeg)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .ready, "Decoded JPEG → PNG adds no further loss")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        let decodedJPEG = try Fixtures.rgbaBytes(of: jpeg)
        let png = try Fixtures.rgbaBytes(of: result.outputs[0])
        XCTAssertEqual(decodedJPEG.bytes, png.bytes,
                       "PNG must reproduce the decoded JPEG samples exactly")
    }

    // MARK: - Alpha gating

    func testAlphaSourceToJPEGIsBlockedInLossless() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "alpha")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasAlpha)

        let plan = planner.plan(source: info, target: target("jpeg"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "alpha.unsupported" })
    }

    func testAlphaSourceToJPEGAllowedInHighestQualityWithWarning() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "alpha")
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("jpeg"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.status.isConvertible)
        XCTAssertTrue(plan.changes.contains { $0.code == "alpha.flattened" })

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("jpeg"))
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertFalse(try inspector.inspect(url: result.outputs[0]).hasAlpha,
                       "Flattened JPEG must have no alpha")
    }

    // MARK: - Honest gap: WebP cannot be written natively

    func testWebPTargetIsBlockedBecauseMacOSCannotWriteIt() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        let webp = target("webp")
        XCTAssertFalse(webp.canWrite, "Documenting real macOS behavior: WebP is read-only via Image I/O")
        let plan = planner.plan(source: info, target: webp,
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked)
    }

    // MARK: - Naming and safety

    func testCollisionNamingNeverOverwrites() throws {
        let dir = TempDir()
        let namer = OutputNamer()
        let a = namer.uniqueURL(in: dir.url, baseName: "pic", fileExtension: "png")
        try Data("x".utf8).write(to: a)
        let b = namer.uniqueURL(in: dir.url, baseName: "pic", fileExtension: "png")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(b.lastPathComponent, "pic-1.png")

        // A second run must skip both the existing file and the reserved name.
        try Data("y".utf8).write(to: b)
        let c = namer.uniqueURL(in: dir.url, baseName: "pic", fileExtension: "png")
        XCTAssertEqual(c.lastPathComponent, "pic-2.png")
    }

    func testCancelLeavesNoPartialOrTempOutput() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(width: 64, height: 64), uti: "public.png",
                                     ext: "png", directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless))

        XCTAssertThrowsError(
            try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                           namer: OutputNamer(), target: target("tiff"),
                                           isCancelled: { true })
        ) { error in
            XCTAssertEqual(error as? ConversionError, .canceled)
        }

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        XCTAssertFalse(remaining.contains { $0.hasSuffix(".tiff") }, "No output should remain")
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".conv3rt-") }, "No temp file should remain")
    }

    // MARK: - Metadata policy

    func testMetadataKeptByDefaultAndRemovedOnRequest() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasGPS, "Fixture should carry GPS")

        // Keep.
        let keepPlan = planner.plan(source: info, target: target("png"),
                                    settings: ConversionSettings(mode: .lossless, metadataPolicy: .keep))
        let kept = try ConversionEngine().convert(plan: keepPlan, outputDirectory: dir.url,
                                                  namer: OutputNamer(), target: target("png"))
        let keptInfo = try inspector.inspect(url: kept.outputs[0])
        XCTAssertTrue(keptInfo.hasGPS, "GPS must be preserved by default")

        // Remove location.
        let removePlan = planner.plan(source: info, target: target("png"),
                                      settings: ConversionSettings(mode: .lossless, metadataPolicy: .removeLocation))
        let removed = try ConversionEngine().convert(plan: removePlan, outputDirectory: dir.url,
                                                     namer: OutputNamer(), target: target("png"))
        let removedInfo = try inspector.inspect(url: removed.outputs[0])
        XCTAssertFalse(removedInfo.hasGPS, "GPS must be gone after removeLocation")
    }
}
