import XCTest
import CoreGraphics
import ImageIO
@testable import Conv3rtCore

/// Color-profile correctness: the inspector must report a carried profile, the
/// planner must block profile-losing targets in Lossless and warn in Highest
/// Quality, and lossless raster targets (PNG/TIFF) must keep the profile.
final class ColorProfileTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared

    private func target(_ id: String) -> FormatCapability {
        guard let t = registry.capability(id: id) else {
            fatalError("missing target \(id)")
        }
        return t
    }

    // MARK: - Fixtures (built here; Fixtures.swift is not modified)

    /// A small opaque image whose pixels are tagged with the Display P3 color
    /// space, so the written file carries a real (non-sRGB) ICC profile.
    private func displayP3Image(width: Int = 8, height: Int = 8) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private func writeP3(_ dir: TempDir, uti: String, ext: String, name: String) throws -> URL {
        try Fixtures.write(displayP3Image(), uti: uti, ext: ext, directory: dir.url, name: name)
    }

    // MARK: - 1. Source carries a profile

    func testPNGSourceWithProfileIsReported() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.png", ext: "png", name: "p3src")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile,
                      "PNG built in Display P3 must report hasColorProfile (name=\(info.colorSpaceName ?? "nil"))")
        XCTAssertNotNil(info.colorSpaceName)
    }

    func testTIFFSourceWithProfileIsReported() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.tiff", ext: "tiff", name: "p3src")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile,
                      "TIFF built in Display P3 must report hasColorProfile (name=\(info.colorSpaceName ?? "nil"))")
    }

    // MARK: - 2. Profile preserved losslessly

    func testPNGWithProfileToPNGLosslessKeepsProfile() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.png", ext: "png", name: "p3src")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible, "PNG→PNG lossless should be convertible")
        XCTAssertFalse(plan.changes.contains { $0.code == "color.profileDropped" },
                       "PNG supports the profile; it must not be reported as dropped")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertTrue(outInfo.hasColorProfile, "PNG→PNG lossless must keep the color profile")
    }

    func testPNGWithProfileToTIFFLosslessKeepsProfile() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.png", ext: "png", name: "p3src")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile)

        let plan = planner.plan(source: info, target: target("tiff"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible, "PNG→TIFF lossless should be convertible")
        XCTAssertFalse(plan.changes.contains { $0.code == "color.profileDropped" })

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("tiff"))
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertTrue(outInfo.hasColorProfile, "PNG→TIFF lossless must keep the color profile")
    }

    // MARK: - 3. Profile-losing target gating (BMP)

    func testProfileBearingPNGToBMPIsBlockedInLossless() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.png", ext: "png", name: "p3src")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile)

        let bmp = target("bmp")
        XCTAssertTrue(bmp.canWrite, "BMP must be a writable target on this system")
        XCTAssertFalse(bmp.supportsColorProfile, "BMP cannot store a color profile")

        let plan = planner.plan(source: info, target: bmp,
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(plan.status, .blocked, "Profile-losing BMP target must be blocked in Lossless")
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "color.profileDropped" },
                      "Blocking reason must be color.profileDropped")
    }

    func testProfileBearingPNGToBMPIsAllowedInHighestQuality() throws {
        let dir = TempDir()
        let src = try writeP3(dir, uti: "public.png", ext: "png", name: "p3src")
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("bmp"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isConvertible, "BMP must be allowed in Highest Quality")
        XCTAssertTrue(plan.warnings.contains { $0.code == "color.profileDropped" },
                      "Highest Quality must still warn that the profile is dropped")
    }

    // MARK: - 4. Display P3 round-trip

    func testDisplayP3ImageIsInspectedAndSurvivesPNGToPNG() throws {
        let dir = TempDir()
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        XCTAssertEqual(p3.name, CGColorSpace.displayP3,
                       "Machine must expose the Display P3 color space")

        let src = try Fixtures.write(displayP3Image(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "p3")
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.hasColorProfile, "Display P3 image must inspect as having a profile")

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertTrue(outInfo.hasColorProfile, "Display P3 profile must survive PNG→PNG lossless")
    }
}
