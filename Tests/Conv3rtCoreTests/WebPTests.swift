import XCTest
import ImageIO
@testable import Conv3rtCore

/// Verifies the bundled-libwebp write path, including the trap the spec calls
/// out: RGB values under fully transparent pixels must survive a lossless WebP
/// encode.
final class WebPTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    func testWebPIsNowWritable() {
        XCTAssertTrue(target("webp").canWrite, "Bundled libwebp should make WebP a writable target")
    }

    func testPNGtoWebPLosslessKeepsOpaqueSamples() throws {
        let dir = TempDir()
        // A lossless-capable source without a color profile (PNG has none by
        // default here), so Lossless WebP is allowed.
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.status.isConvertible, "PNG→WebP lossless should be allowed: \(plan.summary)")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        XCTAssertEqual(result.outputs.count, 1)
        let out = result.outputs[0]
        XCTAssertTrue(inspector.isReadable(url: out))

        let a = try Fixtures.rawRGBA(of: src)
        let b = try Fixtures.rawRGBA(of: out)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "Lossless WebP must preserve every sample")
    }

    func testLosslessWebPPreservesRGBUnderTransparentPixels() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.transparentRGBSample(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "alpha")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasAlpha)

        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible, plan.summary)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        let b = try Fixtures.rawRGBA(of: result.outputs[0])

        // Pixel index 2 is fully transparent and carried RGB (30,30,30).
        XCTAssertEqual(b.bytes[8], 30, "RGB under a fully transparent pixel must survive exact lossless WebP")
        XCTAssertEqual(b.bytes[9], 30)
        XCTAssertEqual(b.bytes[10], 30)
        XCTAssertEqual(b.bytes[11], 0, "The pixel must still be fully transparent")

        let a = try Fixtures.rawRGBA(of: src)
        XCTAssertEqual(a.bytes, b.bytes, "The whole image must round-trip exactly")
    }

    func testWebPMetadataIsReportedAsPreserved() throws {
        let dir = TempDir()
        let src = try Fixtures.pngWithMetadata(directory: dir.url)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality, metadataPolicy: .keep))
        XCTAssertTrue(plan.changes.contains { $0.code == "meta.keep" },
                      "WebP now writes EXIF/GPS/XMP, so metadata is reported as preserved")
    }
}
