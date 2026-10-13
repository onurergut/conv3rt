#if CONV3RT_AVIF
import XCTest
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
