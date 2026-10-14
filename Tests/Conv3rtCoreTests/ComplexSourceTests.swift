import XCTest
import CoreGraphics
import ImageIO
import AppKit
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

    func testPDFInspectionDoesNotRequestRasterFrames() throws {
        let dir = TempDir()
        let url = try Fixtures.pdfFixture(directory: dir.url, pages: 3)
        let pdf = try XCTUnwrap(PDFFrameProvider(url: url))
        let counting = CountingFrameProvider(base: pdf)
        let info = try inspector.inspectProvider(counting, url: url, uti: "com.adobe.pdf",
                                                  declaredUTI: "com.adobe.pdf", fileSize: 0)
        XCTAssertEqual(counting.imageRequests, 0)
        XCTAssertEqual(info.pageCount, 3)
        XCTAssertEqual(info.pixelWidth, 400)
        XCTAssertEqual(info.pixelHeight, 400)
        XCTAssertEqual(info.bitsPerComponent, 8)
        XCTAssertEqual(info.bitsPerPixel, 32)
        XCTAssertEqual(info.decodedByteCount, 3 * 400 * 400 * 4)
    }

    func testPDFToPNGIsBlockedInLosslessAndAllowedInHighestQuality() throws {
        let dir = TempDir()
        let pdf = try Fixtures.pdfFixture(directory: dir.url)
        let info = try inspector.inspect(url: pdf)

        // Lossless: rasterizing a structural source is never lossless, so block.
        let losslessPlan = planner.plan(source: info, target: target("png"),
                                        settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        XCTAssertTrue(losslessPlan.isStructural, "PDF export is a structural rasterization")
        XCTAssertEqual(losslessPlan.status, .blocked)
        XCTAssertTrue(losslessPlan.blockingChanges.contains { $0.code == "structural.export" })

        // Highest Quality: allowed, and labeled as structural.
        let hqPlan = planner.plan(source: info, target: target("png"),
                                  settings: ConversionSettings(mode: .highestQuality, framePolicy: .exportAll))
        XCTAssertTrue(hqPlan.isStructural)
        XCTAssertTrue(hqPlan.isConvertible)

        let result = try ConversionEngine().convert(plan: hqPlan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(inspector.isReadable(url: result.outputs[0]))
    }

    func testPDFExportAllPreservesPageOrderAndRenderedPixels() throws {
        let source = TempDir(), output = TempDir(), reference = TempDir()
        let url = try Fixtures.pdfFixture(directory: source.url, pages: 3)
        let provider = try XCTUnwrap(PDFFrameProvider(url: url))
        let info = try inspector.inspect(url: url)
        let png = target("png")
        let plan = planner.plan(source: info, target: png,
                                settings: ConversionSettings(mode: .highestQuality, framePolicy: .exportAll))
        XCTAssertTrue(plan.isConvertible, plan.summary)
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: output.url,
                                                    namer: OutputNamer(), target: png)
        XCTAssertEqual(result.outputs.count, 3)
        for (index, actualURL) in result.outputs.enumerated() {
            let image = try XCTUnwrap(provider.image(at: index))
            let expectedURL = try Fixtures.write(image, uti: "public.png", ext: "png",
                                                 directory: reference.url, name: "page-\(index)")
            let expected = try Fixtures.rawRGBA(of: expectedURL)
            let actual = try Fixtures.rawRGBA(of: actualURL)
            XCTAssertEqual(actual.width, expected.width)
            XCTAssertEqual(actual.height, expected.height)
            XCTAssertEqual(actual.bytes, expected.bytes)
        }
    }

    func testSVGProviderDefersRasterizationUntilImageIsRequested() throws {
        let dir = TempDir()
        let url = try Fixtures.svgFixture(directory: dir.url)
        let provider = try XCTUnwrap(SVGFrameProvider(url: url))
        XCTAssertNil(provider.renderedImage)
        XCTAssertNil(provider.image(at: -1))
        XCTAssertNil(provider.image(at: 1))
        XCTAssertNil(provider.renderedImage)
        let first = try XCTUnwrap(provider.image(at: 0))
        XCTAssertTrue(first === provider.image(at: 0))
    }

    func testLazySVGMatchesNativeRasterPrecisionAndProfile() throws {
        let dir = TempDir()
        let url = dir.url.appendingPathComponent("fractional.svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="64.25" height="31.5">
        <rect width="64.25" height="31.5" fill="#3366cc" fill-opacity="0.5"/>
        </svg>
        """.write(to: url, atomically: true, encoding: .utf8)
        for scale: CGFloat in [1, 2, 3] {
            let native = try XCTUnwrap(NSImage(contentsOf: url))
            var rect = NSRect(origin: .zero, size: NSSize(width: native.size.width * scale,
                                                        height: native.size.height * scale))
            let expected = try XCTUnwrap(native.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            let provider = try XCTUnwrap(SVGFrameProvider(url: url, scale: scale))
            XCTAssertNil(provider.renderedImage)
            let actual = try XCTUnwrap(provider.image(at: 0))
            XCTAssertEqual(actual.width, expected.width)
            XCTAssertEqual(actual.height, expected.height)
            XCTAssertEqual(actual.bitsPerComponent, expected.bitsPerComponent)
            XCTAssertEqual(actual.bitsPerPixel, expected.bitsPerPixel)
            XCTAssertEqual(actual.bitmapInfo, expected.bitmapInfo)
            XCTAssertEqual(actual.colorSpace?.copyICCData() as Data?, expected.colorSpace?.copyICCData() as Data?)
            XCTAssertEqual(actual.dataProvider?.data as Data?, expected.dataProvider?.data as Data?)
            XCTAssertTrue(actual === provider.image(at: 0))
            XCTAssertTrue(provider.properties(at: -1).isEmpty)
        }
    }

    func testPDFInspectionMatchesItsRenderedLayoutAtDifferentDPI() throws {
        let dir = TempDir()
        let url = try Fixtures.pdfFixture(directory: dir.url)
        for dpi: CGFloat in [72, 144, 300] {
            let provider = try XCTUnwrap(PDFFrameProvider(url: url, dpi: dpi))
            let metadata = try XCTUnwrap(provider.inspection(at: 0))
            let actual = FrameInspection(image: try XCTUnwrap(provider.image(at: 0)))
            XCTAssertEqual(metadata.width, actual.width)
            XCTAssertEqual(metadata.height, actual.height)
            XCTAssertEqual(metadata.bitsPerComponent, actual.bitsPerComponent)
            XCTAssertEqual(metadata.bitsPerPixel, actual.bitsPerPixel)
            XCTAssertEqual(metadata.bytesPerRow, actual.bytesPerRow)
            XCTAssertEqual(metadata.hasAlpha, actual.hasAlpha)
            XCTAssertEqual(metadata.colorSpaceName, actual.colorSpaceName)
            XCTAssertNil(provider.inspection(at: -1))
            XCTAssertNil(provider.inspection(at: 1))
        }
    }

    func testCorruptDocumentsAreNotReadable() throws {
        let dir = TempDir()
        for name in ["broken.pdf", "broken.svg"] {
            let url = dir.url.appendingPathComponent(name)
            try Data("Not a document".utf8).write(to: url)
            XCTAssertFalse(inspector.isReadable(url: url))
            XCTAssertThrowsError(try inspector.inspect(url: url))
        }
    }

    func testPDFInspectionRejectsOversizedLaterPage() throws {
        let dir = TempDir()
        let url = dir.url.appendingPathComponent("oversized.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &bounds, nil))
        for size in [CGSize(width: 10, height: 10), CGSize(width: 100_000, height: 100_000)] {
            var page = CGRect(origin: .zero, size: size)
            let data = withUnsafeBytes(of: &page) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
            context.endPDFPage()
        }
        context.closePDF()
        XCTAssertNil(PDFFrameProvider(url: url))
        XCTAssertFalse(inspector.isReadable(url: url))
        XCTAssertThrowsError(try inspector.inspect(url: url))
    }

    func testRasterWithDocumentExtensionIsStillDetectedByContent() throws {
        let dir = TempDir()
        for ext in ["pdf", "svg"] {
            let url = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: ext,
                                         directory: dir.url)
            XCTAssertTrue(inspector.isReadable(url: url))
            XCTAssertEqual(try inspector.inspect(url: url).detectedUTI, "public.png")
        }
    }

    func testSVGInspectionRetainsExactNativeMetadata() throws {
        let dir = TempDir()
        let url = try Fixtures.svgFixture(directory: dir.url)
        let image = try XCTUnwrap(SVGFrameProvider(url: url)?.image(at: 0))
        let expected = FrameInspection(image: image)
        let info = try inspector.inspect(url: url)
        XCTAssertEqual(info.pixelWidth, expected.width)
        XCTAssertEqual(info.pixelHeight, expected.height)
        XCTAssertEqual(info.bitsPerComponent, expected.bitsPerComponent)
        XCTAssertEqual(info.bitsPerPixel, expected.bitsPerPixel)
        XCTAssertEqual(info.hasAlpha, expected.hasAlpha)
        XCTAssertEqual(info.colorSpaceName, expected.colorSpaceName)
        XCTAssertEqual(info.decodedByteCount, Double(expected.bytesPerRow) * Double(expected.height))
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

    func testPSDIsExportableAsRaster() throws {
        let dir = TempDir()
        // Image I/O can write a merged PSD; that is exactly the "complex source"
        // shape conv3rt ingests (flattened image, no editable layers).
        let psd = try Fixtures.write(Fixtures.manyColors(), uti: "com.adobe.photoshop-image",
                                     ext: "psd", directory: dir.url, name: "doc")
        let info = try inspector.inspect(url: psd)
        XCTAssertEqual(info.detectedUTI, "com.adobe.photoshop-image")

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isStructural, "PSD export is a flattened raster")
        XCTAssertTrue(plan.isConvertible, plan.summary)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertEqual(try inspector.inspect(url: result.outputs[0]).detectedUTI, "public.png")
    }

    private final class CountingFrameProvider: InspectableFrameProvider {
        let base: any SourceFrameProvider
        var imageRequests = 0
        var frameCount: Int { base.frameCount }
        var unitName: String { base.unitName }
        var isAnimated: Bool { base.isAnimated }

        init(base: any SourceFrameProvider) { self.base = base }

        func image(at index: Int) -> CGImage? {
            imageRequests += 1
            return base.image(at: index)
        }

        func properties(at index: Int) -> [CFString: Any] { base.properties(at: index) }
        func inspection(at index: Int) -> FrameInspection? {
            (base as? any InspectableFrameProvider)?.inspection(at: index)
        }
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
