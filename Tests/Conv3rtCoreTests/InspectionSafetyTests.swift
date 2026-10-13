import XCTest
import ImageIO
import CoreGraphics
@testable import Conv3rtCore

final class InspectionSafetyTests: XCTestCase {
    private func gray(width: Int, height: Int, depth: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: depth, bytesPerRow: width * (depth / 8),
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func mixedTIFF(in directory: URL, metadata: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("mixed.tiff")
        let images = [try gray(width: 2, height: 3, depth: 8),
                      try gray(width: 20, height: 30, depth: 16), Fixtures.rgbaSample()]
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
                                                                        "public.tiff" as CFString, 3, nil))
        for (index, image) in images.enumerated() {
            let props: [CFString: Any] = metadata && index == 2 ? [
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "later page"],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0,
                                                kCGImagePropertyGPSLatitudeRef: "N"],
                kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCObjectName: "later page"],
            ] : [:]
            CGImageDestinationAddImage(destination, image, props as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func animationInfo(durations: [Double], loop: Int? = 0,
                               width: Int = 8) -> ImageInfo {
        ImageInfo(url: URL(fileURLWithPath: "/tmp/animation.gif"), detectedUTI: "com.compuserve.gif",
                  declaredUTI: "com.compuserve.gif", fileSize: 0, pixelWidth: width, pixelHeight: 8,
                  frameCount: 2, pageCount: 1, frameDurations: durations, loopCount: loop,
                  canvasWidth: width, canvasHeight: 8, bitsPerComponent: 8, bitsPerPixel: 32,
                  hasAlpha: true, colorModel: "RGB", colorSpaceName: nil, hasColorProfile: false,
                  exifOrientation: nil, hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false)
    }

    private func target(_ id: String) throws -> FormatCapability {
        var target = try XCTUnwrap(FormatCatalog.all.first { $0.id == id })
        target.canWrite = true
        return target
    }

    func testLaterPagesContributeDepthAlphaAndResourceCost() throws {
        let directory = TempDir()
        let info = try ImageInspector().inspect(url: mixedTIFF(in: directory.url))
        XCTAssertEqual(info.pixelWidth, 2, "UI dimensions remain those of the first page")
        XCTAssertEqual(info.pixelHeight, 3)
        XCTAssertEqual(info.bitsPerComponent, 16)
        XCTAssertEqual(info.bitsPerPixel, 32)
        XCTAssertTrue(info.hasAlpha)
        XCTAssertEqual(info.decodedByteCount, 1_270) // 2×3×1 + 20×30×2 + 4×4×4.
        let plan = ConversionPlanner(resourceLimitBytes: 128).plan(source: info, target: try target("tiff"),
                                                                  settings: ConversionSettings())
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "resource.tooLarge" },
                      "The larger later page must count toward the resource limit")
    }

    func testMetadataOnLaterPagesIsInspected() throws {
        let directory = TempDir()
        let info = try ImageInspector().inspect(url: mixedTIFF(in: directory.url, metadata: true))
        XCTAssertTrue(info.hasEXIF)
        XCTAssertTrue(info.hasGPS)
        XCTAssertTrue(info.hasIPTC)
    }

    func testAPNGIsClassifiedAsAnimationByInspectionAndProvider() throws {
        let directory = TempDir()
        let url = directory.url.appendingPathComponent("animated.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
                                                                        "public.png" as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary:
            [kCGImagePropertyAPNGLoopCount: 3]] as CFDictionary)
        for (index, duration) in [0.01, 0.03].enumerated() {
            let image = index == 0 ? Fixtures.rgbaSample() : Fixtures.manyColors(width: 4, height: 4)
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary:
                [kCGImagePropertyAPNGDelayTime: duration,
                 kCGImagePropertyAPNGUnclampedDelayTime: duration]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let info = try ImageInspector().inspect(url: url)
        XCTAssertTrue(info.isAnimated)
        XCTAssertEqual(info.frameCount, 2)
        XCTAssertEqual(info.pageCount, 1)
        // Image I/O exposes APNG's delays as Float32-backed numbers. Inspection
        // must keep those reported values rather than substitute playback delays.
        XCTAssertEqual(info.frameDurations, [0.009999999776482582, 0.029999999329447746])
        XCTAssertEqual(info.loopCount, 3)
        let provider = try XCTUnwrap(ImageIOFrameProvider(url: url))
        XCTAssertTrue(provider.isAnimated)
        XCTAssertEqual(provider.unitName, "frame")
    }

    func testWebPInspectionPreservesContainerLoopCountAndUnclampedTiming() throws {
        let directory = TempDir()
        let url = directory.url.appendingPathComponent("animated.webp")
        let data = try WebPEncoder.encodeAnimated(frames: [
            (Fixtures.rgbaSample(), 0.01), (Fixtures.manyColors(width: 4, height: 4), 0.023)
        ], lossless: true, quality: 1, loopCount: 7)
        try data.write(to: url)
        let info = try ImageInspector().inspect(url: url)
        XCTAssertEqual(info.loopCount, 7)
        XCTAssertEqual(info.frameDurations, [0.01, 0.023])
    }

    func testUnknownAnimationTimingBlocksLosslessPreservation() throws {
        let info = animationInfo(durations: [])
        for policy in [FramePolicy.undecided, .exportAll] {
            let plan = ConversionPlanner().plan(source: info, target: try target("webp"),
                                                settings: ConversionSettings(mode: .lossless, framePolicy: policy))
            XCTAssertEqual(plan.status, .blocked)
            XCTAssertTrue(plan.blockingChanges.contains { $0.code == "animation.timing" })
            XCTAssertFalse(plan.changes.contains { $0.code == "frames.preserved" })
        }
    }

    func testUnknownTimingWarnsInHighestQuality() throws {
        let plan = ConversionPlanner().plan(source: animationInfo(durations: [0.1]), target: try target("webp"),
                                            settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isConvertible)
        XCTAssertTrue(plan.warnings.contains { $0.code == "animation.timing" })
        XCTAssertFalse(plan.changes.contains { $0.code == "frames.preserved" })
    }

    func testWebPTimingMustBeExactlyRepresentableInLossless() throws {
        for durations in [[0.0005, 0.1], [Double.nan, 0.1], [0, 0.1]] {
            let plan = ConversionPlanner().plan(source: animationInfo(durations: durations),
                                                target: try target("webp"), settings: ConversionSettings())
            XCTAssertTrue(plan.blockingChanges.contains { $0.code == "animation.timing" })
        }
    }

    func testWebPDimensionLimitIsBlockedBeforeEncoding() throws {
        let plan = ConversionPlanner().plan(source: animationInfo(durations: [0.1, 0.1], width: 16_384),
                                            target: try target("webp"),
                                            settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "target.dimensions" })
    }

    func testEightBitCatalogTargetsBlockSixteenBitSources() throws {
        let directory = TempDir()
        let info = try ImageInspector().inspect(url: Fixtures.gray16PNG(directory: directory.url))
        for id in ["bmp", "tga", "ico", "icns"] {
            let plan = ConversionPlanner().plan(source: info, target: try target(id),
                                                settings: ConversionSettings(mode: .lossless,
                                                                             framePolicy: .exportAll))
            XCTAssertTrue(plan.blockingChanges.contains { $0.code == "depth.reduced" }, "\(id)")
        }
    }

    func testCanonicalTimingUsesUnclampedValuesForEverySupportedDictionary() throws {
        let keys: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (dictionary, unclamped, clamped) in keys {
            XCTAssertEqual(SourceAnimation.duration(in: [dictionary: [unclamped: 0.01, clamped: 0.1]]), 0.01)
            XCTAssertEqual(SourceAnimation.duration(in: [dictionary: [unclamped: 0.0, clamped: 0.1]]), 0.0)
            XCTAssertEqual(SourceAnimation.duration(in: [dictionary: [clamped: 0.03]]), 0.03)
            XCTAssertNil(SourceAnimation.duration(in: [dictionary: [unclamped: Double.nan, clamped: 0.1]]))
        }
    }

    func testCanonicalAnimationClassificationIncludesAllAnimationFamilies() {
        for uti in ["public.png", "com.compuserve.gif", "public.heics", "org.webmproject.webp",
                    "public.avif", "public.jpeg-xl"] {
            XCTAssertTrue(SourceAnimation.isAnimated(uti: uti, count: 2, properties: [:]), uti)
            XCTAssertFalse(SourceAnimation.isAnimated(uti: uti, count: 1, properties: [:]), uti)
        }
        XCTAssertFalse(SourceAnimation.isAnimated(uti: "public.tiff", count: 2, properties: [:]))
        XCTAssertEqual(SourceAnimation.loopCount(in: [kCGImagePropertyWebPDictionary:
            [kCGImagePropertyWebPLoopCount: 7]]), 7)
        XCTAssertEqual(SourceAnimation.loopCount(in: [kCGImagePropertyPNGDictionary:
            [kCGImagePropertyAPNGLoopCount: 3]]), 3)
    }

    func testQOIsImplicitColorSpaceDoesNotClaimAnEmbeddedProfile() throws {
        let directory = TempDir()
        let url = directory.url.appendingPathComponent("plain.qoi")
        try QOICodec.encode(Fixtures.rgbaSample()).write(to: url)
        let info = try ImageInspector().inspect(url: url)
        XCTAssertFalse(info.hasColorProfile)
        let plan = ConversionPlanner().plan(source: info, target: try target("qoi"),
                                            settings: ConversionSettings())
        XCTAssertTrue(plan.isConvertible)
        XCTAssertFalse(plan.changes.contains { $0.code == "color.profileDropped" })
    }

    func testProviderResourceTotalIncludesLargerLaterPDFPage() throws {
        let directory = TempDir()
        let url = directory.url.appendingPathComponent("different-pages.pdf")
        var box = CGRect(x: 0, y: 0, width: 20, height: 20)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for size in [CGSize(width: 20, height: 20), CGSize(width: 200, height: 100)] {
            var page = CGRect(origin: .zero, size: size)
            let data = withUnsafeBytes(of: &page) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
            context.setFillColor(gray: 0.3, alpha: 1)
            context.fill(page)
            context.endPDFPage()
        }
        context.closePDF()
        let info = try ImageInspector().inspect(url: url)
        XCTAssertEqual(info.pixelWidth, 40)
        XCTAssertEqual(info.pixelHeight, 40)
        XCTAssertEqual(info.canvasWidth, 400)
        XCTAssertEqual(info.canvasHeight, 200)
        XCTAssertGreaterThan(try XCTUnwrap(info.decodedByteCount), 300_000)
        let plan = ConversionPlanner(resourceLimitBytes: 100_000).plan(source: info, target: try target("tiff"),
                                                                      settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "resource.tooLarge" })
    }

    func testCustomXMPNamespaceOnLaterPageIsInspected() throws {
        let directory = TempDir()
        let url = directory.url.appendingPathComponent("later-xmp.tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
                                                                        "public.tiff" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, try gray(width: 2, height: 3, depth: 8), nil)
        let metadata = CGImageMetadataCreateMutable()
        let namespace = "https://example.com/conv3rt/1.0/" as CFString
        XCTAssertTrue(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, "sample" as CFString, nil))
        let tag = try XCTUnwrap(CGImageMetadataTagCreate(namespace, "sample" as CFString,
                                                        "Label" as CFString, .string, "later page" as CFString))
        XCTAssertTrue(CGImageMetadataSetTagWithPath(metadata, nil, "sample:Label" as CFString, tag))
        CGImageDestinationAddImageAndMetadata(destination, Fixtures.rgbaSample(), metadata, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let stored = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source, 1, nil))
        XCTAssertNotNil(CGImageMetadataCopyTagWithPath(stored, nil, "sample:Label" as CFString))
        XCTAssertTrue(try ImageInspector().inspect(url: url).hasXMP)
    }

    func testSplittingAnimationCannotBeLabeledLossless() throws {
        let info = animationInfo(durations: [0.1, 0.1])
        let png = try target("png")
        let lossless = ConversionPlanner().plan(source: info, target: png,
                                                settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        XCTAssertEqual(lossless.status, .blocked)
        XCTAssertTrue(lossless.blockingChanges.contains { $0.code == "frames.exportAll" })
        let quality = ConversionPlanner().plan(source: info, target: png,
                                               settings: ConversionSettings(mode: .highestQuality, framePolicy: .exportAll))
        XCTAssertTrue(quality.isConvertible)
        XCTAssertTrue(quality.expandsFramesOrPages)
        XCTAssertTrue(quality.warnings.contains { $0.code == "frames.exportAll" })
    }

    func testRemoveLocationDisclosesLimitedMetadataForEveryMetadataKind() throws {
        let bmp = try target("bmp")
        let flags = [(true, false, false, false), (false, true, false, false),
                     (false, false, true, false), (false, false, false, true),
                     (false, false, false, false)]
        for (exif, gps, iptc, xmp) in flags {
            let info = ImageInfo(url: URL(fileURLWithPath: "/tmp/metadata.png"),
                                 detectedUTI: "public.png", declaredUTI: "public.png", fileSize: 0,
                                 pixelWidth: 8, pixelHeight: 8, frameCount: 1, pageCount: 1,
                                 frameDurations: [], loopCount: nil, canvasWidth: 8, canvasHeight: 8,
                                 bitsPerComponent: 8, bitsPerPixel: 24, hasAlpha: false, colorModel: "RGB",
                                 colorSpaceName: nil, hasColorProfile: false, exifOrientation: nil,
                                 hasEXIF: exif, hasGPS: gps, hasIPTC: iptc, hasXMP: xmp)
            let plan = ConversionPlanner().plan(source: info, target: bmp,
                                                settings: ConversionSettings(mode: .highestQuality,
                                                                             metadataPolicy: .removeLocation))
            XCTAssertEqual(plan.warnings.contains { $0.code == "meta.limited" }, exif || gps || iptc || xmp)
            XCTAssertFalse(plan.changes.contains {
                ($0.code == "meta.removeGPS" || $0.code == "meta.noGPS") && $0.message.contains("other metadata is kept")
            })
            let supported = ConversionPlanner().plan(source: info, target: try target("png"),
                                                      settings: ConversionSettings(mode: .highestQuality,
                                                                                   metadataPolicy: .removeLocation))
            XCTAssertFalse(supported.changes.contains { $0.code == "meta.limited" })
        }
    }

    func testUnsupportedDisplayOrientationBlocksLosslessAndWarnsHighestQuality() throws {
        // Orientation is a top-level image property; an EXIF dictionary is
        // not required for the display transform to need preservation.
        let info = ImageInfo(url: URL(fileURLWithPath: "/tmp/oriented.png"),
                             detectedUTI: "public.png", declaredUTI: "public.png", fileSize: 0,
                             pixelWidth: 8, pixelHeight: 16, frameCount: 1, pageCount: 1,
                             frameDurations: [], loopCount: nil, canvasWidth: 8, canvasHeight: 16,
                             bitsPerComponent: 8, bitsPerPixel: 24, hasAlpha: false, colorModel: "RGB",
                             colorSpaceName: nil, hasColorProfile: false, exifOrientation: 6,
                             hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false)
        for id in ["qoi", "pcx", "pfm", "dds", "avif"] {
            let lossless = ConversionPlanner().plan(source: info, target: try target(id),
                                                    settings: ConversionSettings(mode: .lossless,
                                                                                 metadataPolicy: .remove))
            XCTAssertTrue(lossless.blockingChanges.contains { $0.code == "orientation.unsupported" }, id)
            let quality = ConversionPlanner().plan(source: info, target: try target(id),
                                                   settings: ConversionSettings(mode: .highestQuality,
                                                                                metadataPolicy: .remove))
            XCTAssertTrue(quality.isConvertible, id)
            XCTAssertTrue(quality.warnings.contains { $0.code == "orientation.unsupported" }, id)
        }
        for id in ["png", "webp", "jxl"] {
            let preserved = ConversionPlanner().plan(source: info, target: try target(id),
                                                     settings: ConversionSettings(mode: .highestQuality,
                                                                                  metadataPolicy: .remove))
            XCTAssertFalse(preserved.changes.contains { $0.code == "orientation.unsupported" })
            XCTAssertTrue(preserved.changes.contains {
                $0.message == "Display orientation will be preserved."
            })
        }
    }
}
