import XCTest
import ImageIO
import CoreGraphics
@testable import Conv3rtCore

/// High-bit-depth correctness: 16-bit sources must not be silently reduced, and
/// a 16-bit → 8-bit-only target must be blocked in Lossless mode.
final class DepthTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared

    private func target(_ id: String) -> FormatCapability {
        guard let t = registry.capability(id: id) else {
            fatalError("missing target \(id)")
        }
        return t
    }

    // MARK: - Inspection

    func testGray16PNGInspectsAs16BitPerComponent() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.bitsPerComponent, 16,
                       "A 16-bit grayscale PNG must report 16 bits per component")
        XCTAssertEqual(info.bitsPerPixel, 16, "Gray 16-bit is 16 bits per pixel")
        XCTAssertEqual(info.colorModel, "Gray")
    }

    // MARK: - 16-bit → 16-bit is not reduced

    func testGray16PNGtoPNGLosslessKeeps16Bit() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .ready, "PNG→PNG at 16-bit should be lossless-ready")
        XCTAssertFalse(plan.changes.contains { $0.code == "depth.reduced" })

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)

        let out = try inspector.inspect(url: result.outputs[0])
        XCTAssertEqual(out.bitsPerComponent, 16,
                       "16-bit → 16-bit PNG must not be reduced to 8-bit")

        let srcSamples = try gray16Samples(of: src)
        let outSamples = try gray16Samples(of: result.outputs[0])
        XCTAssertEqual(srcSamples.bits, 16)
        XCTAssertEqual(outSamples.bits, 16)
        XCTAssertEqual(srcSamples.samples, outSamples.samples,
                       "PNG-16 → PNG-16 must preserve every 16-bit sample")
    }

    func testGray16PNGtoTIFFLosslessKeeps16Bit() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .ready, "PNG-16 → TIFF should be lossless-ready")
        XCTAssertFalse(plan.changes.contains { $0.code == "depth.reduced" })

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("tiff"))
        XCTAssertEqual(result.outputs.count, 1)

        let out = try inspector.inspect(url: result.outputs[0])
        XCTAssertEqual(out.bitsPerComponent, 16,
                       "16-bit → 16-bit TIFF must not be reduced to 8-bit")
    }

    // MARK: - 16-bit source into a 16-bit target is convertible

    func testGray16PNGtoTIFFIsConvertibleInLossless() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible,
                      "TIFF supports 16-bit, so a 16-bit source is convertible in Lossless")
        XCTAssertNotEqual(plan.status, .blocked)
    }

    // MARK: - 16-bit → 8-bit-only target

    func testGray16PNGtoJPEGBlockedInLossless() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("jpeg"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked,
                       "Reducing 16-bit to JPEG's 8-bit must block lossless conversion")
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "depth.reduced" },
                      "Blocking change must be coded depth.reduced")
    }

    func testGray16PNGtoJPEGAllowedWithWarningInHighestQuality() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("jpeg"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.status.isConvertible,
                      "Highest Quality must allow the 16-bit → 8-bit reduction")
        XCTAssertFalse(plan.blockingChanges.contains { $0.code == "depth.reduced" })
        XCTAssertTrue(plan.warnings.contains { $0.code == "depth.reduced" },
                      "Reduction must surface as a depth.reduced warning")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("jpeg"))
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(try inspector.inspect(url: result.outputs[0]).bitsPerComponent, 8)
    }

    // MARK: - Helpers

    /// Decodes a file and reads back grayscale 16-bit sample words.
    private func gray16Samples(of url: URL) throws -> (samples: [UInt16], bits: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "depthtests", code: 1)
        }
        let width = image.width, height = image.height
        let space = CGColorSpaceCreateDeviceGray()
        var buf = [UInt16](repeating: 0, count: width * height)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 16, bytesPerRow: width * 2,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw NSError(domain: "depthtests", code: 2) }
        return (buf, image.bitsPerComponent)
    }
}
