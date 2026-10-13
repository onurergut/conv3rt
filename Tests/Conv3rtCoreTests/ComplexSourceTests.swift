import XCTest
@testable import Conv3rtCore

/// PDF and SVG are not decodable by Image I/O. These verify the PDFKit/AppKit
/// fallback path actually works end to end, and that the result is labeled as a
/// structural (not lossless) conversion.
final class ComplexSourceTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    func testPDFIsInspectedViaFallback() throws {
        let dir = TempDir()
        let pdf = try Fixtures.pdfFixture(directory: dir.url, pages: 2)
        let info = try inspector.inspect(url: pdf)
        XCTAssertEqual(info.detectedUTI, "com.adobe.pdf")
        XCTAssertEqual(info.pageCount, 2, "Two-page PDF should report 2 pages")
        XCTAssertGreaterThan(info.pixelWidth, 0)
    }

    func testPDFToPNGIsStructuralAndAllowed() throws {
        let dir = TempDir()
        let pdf = try Fixtures.pdfFixture(directory: dir.url)
        let info = try inspector.inspect(url: pdf)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        XCTAssertTrue(plan.isStructural, "PDF export is a structural rasterization")
        XCTAssertTrue(plan.isConvertible)
        XCTAssertFalse(plan.changes.contains { $0.code == "lossless.unavailable" },
                       "Structural sources are labeled, not blocked as 'no lossless path'")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(inspector.isReadable(url: result.outputs[0]))
    }

    func testSVGIsInspectedAndRasterized() throws {
        let dir = TempDir()
        let svg = try Fixtures.svgFixture(directory: dir.url)
        XCTAssertTrue(inspector.isReadable(url: svg), "SVG should be readable via AppKit")
        let info = try inspector.inspect(url: svg)
        XCTAssertEqual(info.detectedUTI, "public.svg-image")
        XCTAssertGreaterThan(info.pixelWidth, 0)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isStructural)
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)

        // Rasterized output should be a normal PNG we can re-open.
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertEqual(outInfo.detectedUTI, "public.png")
        XCTAssertGreaterThan(outInfo.pixelWidth, 0)
    }

    func testMisnamedFileIsDetectedByContent() throws {
        let dir = TempDir()
        // A real PNG with a .jpg name.
        let png = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "real")
        let wrong = dir.url.appendingPathComponent("pretender.jpg")
        try FileManager.default.moveItem(at: png, to: wrong)

        let info = try inspector.inspect(url: wrong)
        XCTAssertEqual(info.detectedUTI, "public.png", "Content, not extension, decides the type")
        XCTAssertTrue(info.extensionMismatch, "The mismatch should be reported")
    }
}
