import XCTest
import ImageIO
@testable import Conv3rtCore

/// Verifies that the bundled WebP and JPEG XL encoders carry source metadata
/// (EXIF/GPS/XMP) and honor the settings' `metadataPolicy`.
///
/// The metadata is embedded in each format's native container channel — the
/// WebP "EXIF"/"XMP " chunks and the JPEG XL "Exif"/"xml " boxes — so Image I/O
/// reports EXIF and GPS when the output is reopened.
final class MetadataWriteTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    /// Converts `src` to `id` under `policy` and re-inspects the written output.
    private func convert(_ src: URL, to id: String, policy: MetadataPolicy,
                         dir: URL) throws -> ImageInfo {
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target(id),
                                settings: ConversionSettings(mode: .highestQuality,
                                                             metadataPolicy: policy))
        XCTAssertTrue(plan.isConvertible, "plan blocked: \(plan.summary)")
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir,
                                                    namer: OutputNamer(), target: target(id))
        XCTAssertEqual(result.outputs.count, 1)
        return try inspector.inspect(url: result.outputs[0])
    }

    // MARK: - WebP

    func testPNGMetadataToWebPKeep() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let srcInfo = try inspector.inspect(url: src)
        XCTAssertTrue(srcInfo.hasEXIF, "fixture should carry EXIF")
        XCTAssertTrue(srcInfo.hasGPS, "fixture should carry GPS")

        let out = try convert(src, to: "webp", policy: .keep, dir: dir.url)
        XCTAssertTrue(out.hasEXIF, "EXIF should survive PNG→WebP (keep)")
        XCTAssertTrue(out.hasGPS, "GPS should survive PNG→WebP (keep)")
    }

    func testPNGMetadataToWebPRemoveLocation() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let out = try convert(src, to: "webp", policy: .removeLocation, dir: dir.url)
        XCTAssertFalse(out.hasGPS, "GPS must be dropped for removeLocation")
        XCTAssertTrue(out.hasEXIF, "other EXIF is kept for removeLocation")
    }

    func testPNGMetadataToWebPRemove() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let out = try convert(src, to: "webp", policy: .remove, dir: dir.url)
        XCTAssertFalse(out.hasEXIF, "EXIF must be dropped for remove")
        XCTAssertFalse(out.hasGPS, "GPS must be dropped for remove")
    }

    // MARK: - JPEG XL

#if CONV3RT_JXL
    func testPNGMetadataToJXLKeep() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let srcInfo = try inspector.inspect(url: src)
        XCTAssertTrue(srcInfo.hasEXIF)
        XCTAssertTrue(srcInfo.hasGPS)

        let out = try convert(src, to: "jxl", policy: .keep, dir: dir.url)
        XCTAssertTrue(out.hasEXIF, "EXIF should survive PNG→JXL (keep)")
        XCTAssertTrue(out.hasGPS, "GPS should survive PNG→JXL (keep)")
    }

    func testPNGMetadataToJXLRemoveLocation() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let out = try convert(src, to: "jxl", policy: .removeLocation, dir: dir.url)
        XCTAssertFalse(out.hasGPS, "GPS must be dropped for removeLocation")
        XCTAssertTrue(out.hasEXIF, "other EXIF is kept for removeLocation")
    }

    func testPNGMetadataToJXLRemove() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let out = try convert(src, to: "jxl", policy: .remove, dir: dir.url)
        XCTAssertFalse(out.hasEXIF, "EXIF must be dropped for remove")
        XCTAssertFalse(out.hasGPS, "GPS must be dropped for remove")
    }
#endif
}
