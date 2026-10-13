import XCTest
@testable import Conv3rtCore

/// Proves the bundled codecs (QOI, PCX, PFM) are wired into the engine end to
/// end, not just passing as isolated unit tests: source detection, planning,
/// conversion, and verification through the public API.
final class IntegrationCodecTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    private func convert(_ src: URL, to id: String, lossless: Bool, in dir: URL) throws -> URL {
        let info = try inspector.inspect(url: src)
        let t = target(id)
        let plan = planner.plan(source: info, target: t,
                                settings: ConversionSettings(mode: lossless ? .lossless : .highestQuality,
                                                             framePolicy: .exportAll))
        XCTAssertTrue(plan.isConvertible, "\(id): \(plan.summary)")
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir,
                                                    namer: OutputNamer(), target: t)
        return try XCTUnwrap(result.outputs.first)
    }

    func testBundledCodecsAreWritableTargets() {
        for id in ["qoi", "pcx", "pfm", "dds"] {
            XCTAssertTrue(target(id).canWrite, "\(id) should be writable")
            XCTAssertTrue(target(id).canRead, "\(id) should be readable")
        }
    }

    func testPNGtoDDSRoundTripIsLossless() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let dds = try convert(src, to: "dds", lossless: false, in: dir.url)
        let data = try Data(contentsOf: dds)
        let decoded = try DDSCodec.decode(data)
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 32)
        let a = try Fixtures.rgbaBytes(of: src)
        let b = try Fixtures.rgbaBytes(of: decoded)
        XCTAssertEqual(a.bytes, b.bytes, "PNG→DDS must be sample-exact")
    }

    func testPNGtoQOIRoundTripIsLosslessThroughTheEngine() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let qoi = try convert(src, to: "qoi", lossless: false, in: dir.url)
        XCTAssertTrue(inspector.isReadable(url: qoi), "QOI output must be re-openable via the bundled decoder")

        let back = try convert(qoi, to: "png", lossless: false, in: dir.url)
        let a = try Fixtures.rawRGBA(of: src)
        let b = try Fixtures.rawRGBA(of: back)
        XCTAssertEqual(a.bytes, b.bytes, "PNG→QOI→PNG must be sample-exact")
    }

    func testPNGtoPCXProducesReadableOutput() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let pcx = try convert(src, to: "pcx", lossless: false, in: dir.url)
        XCTAssertTrue(inspector.isReadable(url: pcx))
        let info = try inspector.inspect(url: pcx)
        XCTAssertEqual(info.pixelWidth, 32)
        XCTAssertEqual(info.pixelHeight, 32)
    }

    func testPNGtoPFMProducesReadableFloatImage() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let pfm = try convert(src, to: "pfm", lossless: false, in: dir.url)
        XCTAssertTrue(inspector.isReadable(url: pfm))
        let info = try inspector.inspect(url: pfm)
        XCTAssertEqual(info.pixelWidth, 32)
        XCTAssertEqual(info.pixelHeight, 32)
    }
}
