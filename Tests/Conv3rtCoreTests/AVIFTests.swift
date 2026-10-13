#if CONV3RT_AVIF
import XCTest
import CoreGraphics
import ImageIO
@testable import Conv3rtCore

/// AVIF (lossy) writing via the bundled libavif + libaom. Compiled only when
/// the libraries have been built (scripts/build-avif.sh).
final class AVIFTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    func testAVIFIsWritableWhenBuilt() {
        XCTAssertTrue(target("avif").canWrite)
        XCTAssertTrue(target("avif").canRead)
    }

    func testPNGtoAVIFProducesReadableOutput() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")

        let plan = planner.plan(source: try inspector.inspect(url: src), target: target("avif"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isConvertible, plan.summary)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("avif"))
        let out = result.outputs[0]
        XCTAssertTrue(inspector.isReadable(url: out), "AVIF output must be re-openable")

        // Re-open via Image I/O (which reads AVIF natively) and check dimensions.
        let reopen = try inspector.inspect(url: out)
        XCTAssertEqual(reopen.pixelWidth, 32)
        XCTAssertEqual(reopen.pixelHeight, 32)
    }

    func testAVIFEmbedsColorProfile() throws {
        let dir = TempDir()
        // A non-sRGB (Display P3) source, so the written file carries a real ICC.
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let src = try Fixtures.write(ctx.makeImage()!, uti: "public.png", ext: "png",
                                     directory: dir.url, name: "p3src")
        XCTAssertTrue(try inspector.inspect(url: src).hasColorProfile)

        let plan = planner.plan(source: try inspector.inspect(url: src), target: target("avif"),
                                settings: ConversionSettings(mode: .highestQuality))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("avif"))
        let reopen = try inspector.inspect(url: result.outputs[0])
        XCTAssertTrue(reopen.hasColorProfile, "AVIF must carry the source ICC profile")
    }

    func testAVIFInLosslessIsBlocked() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let plan = planner.plan(source: try inspector.inspect(url: src), target: target("avif"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "lossless.unavailable" })
    }
}
#endif
