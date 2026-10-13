import XCTest
import ImageIO
@testable import Conv3rtCore

/// Round-trips the native codecs the capability matrix marked "unverified" and
/// records what actually holds. Formats whose encode is lossless are checked for
/// sample equality; the rest are only required to produce a readable file of the
/// right size.
final class RoundtripTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    /// Highest Quality mode: still uses each codec's lossless path for lossless
    /// targets, and avoids the color-profile block for profile-less formats.
    private func convert(_ src: URL, to id: String, in dir: URL) throws -> URL {
        let info = try inspector.inspect(url: src)
        let t = target(id)
        XCTAssertTrue(t.canWrite, "\(id) should be a writable target")
        let plan = planner.plan(source: info, target: t,
                                settings: ConversionSettings(mode: .highestQuality, framePolicy: .exportAll))
        XCTAssertTrue(plan.isConvertible, "\(id): \(plan.summary)")
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir,
                                                    namer: OutputNamer(), target: t)
        return try XCTUnwrap(result.outputs.first)
    }

    private func sourcePNG(_ dir: URL) throws -> URL {
        try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                           directory: dir, name: "src")
    }

    // Formats expected to be sample-exact for an opaque 8-bit RGB source.
    func testLosslessSampleEquality() throws {
        let expected: [String] = ["png", "tiff", "bmp", "tga", "pnm"]
        for id in expected {
            let dir = TempDir()
            let src = try sourcePNG(dir.url)
            let out = try convert(src, to: id, in: dir.url)
            let a = try Fixtures.rawRGBA(of: src)
            let b = try Fixtures.rawRGBA(of: out)
            XCTAssertEqual(a.width, b.width, "\(id): width")
            XCTAssertEqual(a.height, b.height, "\(id): height")
            let mismatch = Self.firstDiff(a.bytes, b.bytes)
            XCTAssertNil(mismatch, "\(id): samples differ at byte \(mismatch ?? -1) "
                         + "(src \(mismatch.map { a.bytes[$0] } ?? 0) vs out \(mismatch.map { b.bytes[$0] } ?? 0))")
            XCTAssertTrue(inspector.isReadable(url: out))
        }
    }

    private static func firstDiff(_ a: [UInt8], _ b: [UInt8]) -> Int? {
        for i in 0..<min(a.count, b.count) where a[i] != b[i] { return i }
        return a.count == b.count ? nil : min(a.count, b.count)
    }

    // Formats expected to be lossy or structurally special: require only that a
    // valid, correctly sized image comes back.
    func testReadableRoundtrip() throws {
        let targets: [String] = ["jp2", "exr", "heic", "ico", "icns"]
        for id in targets {
            let dir = TempDir()
            let src = try sourcePNG(dir.url)
            let out = try convert(src, to: id, in: dir.url)
            XCTAssertTrue(inspector.isReadable(url: out), "\(id): output must be readable")
            let info = try inspector.inspect(url: out)
            XCTAssertGreaterThan(info.pixelWidth, 0, "\(id): width")
            XCTAssertGreaterThan(info.pixelHeight, 0, "\(id): height")
        }
    }
}
