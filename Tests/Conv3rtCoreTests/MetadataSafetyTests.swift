import XCTest
import CoreGraphics
import ImageIO
@testable import Conv3rtCore

final class MetadataSafetyTests: XCTestCase {
    func testPNGKeepPreservesCustomXMP() throws {
        let source = TempDir(), output = TempDir()
        let url = try writeSource(in: source.url, labels: ["custom label"])
        let result = try convert(url, to: "png", policy: .keep, output: output.url)
        XCTAssertEqual(try metadataString(at: result[0], path: "sample:Label"), "custom label")
    }

    func testWebPKeepPreservesDisplayOrientation() throws {
        let source = TempDir(), output = TempDir()
        let url = try writeOrientedSource(in: source.url)
        XCTAssertEqual(try ImageInspector().inspect(url: url).exifOrientation, 6)
        let result = try convert(url, to: "webp", policy: .keep, output: output.url)
        XCTAssertEqual(try ImageInspector().inspect(url: result[0]).exifOrientation, 6)
    }

    func testWebPRemovePreservesDisplayOrientationWithoutPrivateMetadata() throws {
        try assertPrivateMetadataRemovedWithOrientation(target: "webp")
    }

    func testPNGRemovePreservesDisplayOrientationWithoutPrivateMetadata() throws {
        try assertPrivateMetadataRemovedWithOrientation(target: "png")
    }

    func testPNGRemoveRemovesCustomXMPAndLocation() throws {
        let source = TempDir(), output = TempDir()
        let url = try writeSource(in: source.url, labels: ["private label"])
        let result = try convert(url, to: "png", policy: .remove, output: output.url)
        XCTAssertNil(try metadataString(at: result[0], path: "sample:Label"))
        XCTAssertNil(try metadataString(at: result[0], path: "exif:GPSLatitude"))
        XCTAssertFalse(try ImageInspector().inspect(url: result[0]).hasGPS)
    }

    func testPNGRemoveLocationKeepsCustomXMPWithoutGPS() throws {
        let source = TempDir(), output = TempDir()
        let url = try writeSource(in: source.url, labels: ["public label"])
        XCTAssertNotNil(try metadataString(at: url, path: "exif:GPSLatitude"))
        let result = try convert(url, to: "png", policy: .removeLocation, output: output.url)
        XCTAssertEqual(try metadataString(at: result[0], path: "sample:Label"), "public label")
        XCTAssertNil(try metadataString(at: result[0], path: "exif:GPSLatitude"))
        XCTAssertFalse(try ImageInspector().inspect(url: result[0]).hasGPS)
    }

    func testSplitTIFFToPNGPreservesEachPagesOwnMetadata() throws {
        try assertSplitMetadata(target: "png")
    }

    func testSplitTIFFToWebPPreservesEachPagesOwnMetadata() throws {
        try assertSplitMetadata(target: "webp")
    }

    #if CONV3RT_JXL
    func testSplitTIFFToJXLPreservesEachPagesOwnMetadata() throws {
        try assertSplitMetadata(target: "jxl")
    }
    #endif

    func testImageIOMetadataOptionsAlsoPreserveRegularFrameProperties() throws {
        let source = TempDir()
        let url = try writeSource(in: source.url, labels: ["options label"])
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifUserComment] as? String, "options label comment")
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
        XCTAssertEqual((gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue, 41)
        XCTAssertEqual(try metadataString(at: url, path: "sample:Label"), "options label")
    }

    func testProviderMetadataUsesRequestedPageAndPrivacyPolicy() throws {
        let source = TempDir()
        let url = try writeSource(in: source.url, labels: ["first page", "second page"])
        let provider = try XCTUnwrap(ImageIOFrameProvider(url: url))
        let metadata = try XCTUnwrap(provider.metadata(at: 1, policy: .keep))
        XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(metadata, nil, "sample:Label" as CFString) as String?,
                       "second page")
        let stripped = try XCTUnwrap(provider.metadata(at: 1, policy: .removeLocation))
        XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(stripped, nil, "sample:Label" as CFString) as String?,
                       "second page")
        XCTAssertNil(CGImageMetadataCopyTagWithPath(stripped, nil, "exif:GPSLatitude" as CFString))
        XCTAssertNil(provider.metadata(at: 1, policy: .remove))
        let packet = try XCTUnwrap(provider.metadataXMP(includeLocation: true, index: 1))
        let parsed = try XCTUnwrap(CGImageMetadataCreateFromXMPData(Data(packet) as CFData))
        XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(parsed, nil, "sample:Label" as CFString) as String?,
                       "second page")
        let exif = try XCTUnwrap(provider.metadataEXIF(includeLocation: true, index: 1))
        XCTAssertTrue(Data(exif).range(of: Data("second page comment".utf8)) != nil)
        XCTAssertFalse(Data(exif).range(of: Data("first page comment".utf8)) != nil)
    }

    func testProviderSerializesOrientationWithoutPrivateMetadata() throws {
        let source = TempDir()
        let url = try writeOrientedSource(in: source.url)
        let provider = try XCTUnwrap(ImageIOFrameProvider(url: url))
        let payload = try XCTUnwrap(provider.orientationEXIF())
        XCTAssertNil(Data(payload).range(of: Data("private camera comment".utf8)))
        let image = try XCTUnwrap(provider.image(at: 0))
        let output = source.url.appendingPathComponent("orientation-only.webp")
        try WebPEncoder.encode(image: image, lossless: true, quality: 1, exif: payload).write(to: output)
        let info = try ImageInspector().inspect(url: output)
        XCTAssertEqual(info.exifOrientation, 6)
        XCTAssertFalse(info.hasGPS)
        XCTAssertFalse(info.hasEXIF, "No private EXIF fields are added to the orientation-only payload")
    }

    func testProviderSerializesOrientationOnlySources() throws {
        let source = TempDir()
        let url = try Fixtures.write(Fixtures.rgbaSample(width: 3, height: 2), uti: "public.png", ext: "png",
                                     directory: source.url, properties: [kCGImagePropertyOrientation: 6])
        let provider = try XCTUnwrap(ImageIOFrameProvider(url: url))
        let payload = try XCTUnwrap(provider.metadataEXIF(includeLocation: true))
        let output = source.url.appendingPathComponent("kept-orientation.webp")
        try WebPEncoder.encode(image: XCTUnwrap(provider.image(at: 0)), lossless: true, quality: 1,
                               exif: payload).write(to: output)
        XCTAssertEqual(try ImageInspector().inspect(url: output).exifOrientation, 6)
    }

    private func assertSplitMetadata(target: String) throws {
        let source = TempDir(), output = TempDir()
        let url = try writeSource(in: source.url, labels: ["first page", "second page"])
        let result = try convert(url, to: target, policy: .keep, output: output.url)
        XCTAssertEqual(result.count, 2)
        for (index, expected) in ["first page", "second page"].enumerated() {
            // Image I/O reads JXL EXIF but does not expose custom XMP tags.
            // Verify the actual uncompressed XML container box for that format.
            let label = target == "jxl"
                ? try jxlMetadataString(at: result[index], path: "sample:Label")
                : try metadataString(at: result[index], path: "sample:Label")
            XCTAssertEqual(label, expected,
                           "Each exported page must keep its own XMP tag")
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(result[index] as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
            let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
            XCTAssertEqual(exif[kCGImagePropertyExifUserComment] as? String, "\(expected) comment",
                           "Each exported page must keep its own EXIF")
        }
    }

    private func assertPrivateMetadataRemovedWithOrientation(target: String) throws {
        let source = TempDir(), output = TempDir()
        let url = try writeOrientedSource(in: source.url)
        let result = try convert(url, to: target, policy: .remove, output: output.url)
        XCTAssertEqual(try ImageInspector().inspect(url: result[0]).exifOrientation, 6,
                       "Removing private metadata must keep the display orientation")
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(result[0] as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
        XCTAssertFalse(try ImageInspector().inspect(url: result[0]).hasGPS)
    }

    private func writeOrientedSource(in directory: URL) throws -> URL {
        try Fixtures.write(Fixtures.rgbaSample(width: 3, height: 2), uti: "public.png", ext: "png",
                           directory: directory, properties: [
                            kCGImagePropertyOrientation: 6,
                            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private camera comment"],
                            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0,
                                                            kCGImagePropertyGPSLatitudeRef: "N"],
                           ])
    }

    private func convert(_ url: URL, to format: String, policy: MetadataPolicy, output: URL) throws -> [URL] {
        let target = try XCTUnwrap(CapabilityRegistry.shared.capability(id: format))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url), target: target,
                                            settings: ConversionSettings(mode: .highestQuality,
                                                                         metadataPolicy: policy,
                                                                         framePolicy: .exportAll))
        XCTAssertTrue(plan.isConvertible, plan.summary)
        return try ConversionEngine().convert(plan: plan, outputDirectory: output,
                                               namer: OutputNamer(), target: target).outputs
    }

    private func metadataString(at url: URL, index: Int = 0, path: String) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { return nil }
        return CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
    }

    private func jxlMetadataString(at url: URL, path: String) throws -> String? {
        let bytes = [UInt8](try Data(contentsOf: url))
        var offset = 0
        while offset <= bytes.count - 8 {
            let size = (0..<4).reduce(0) { ($0 << 8) | Int(bytes[offset + $1]) }
            let length = size == 0 ? bytes.count - offset : size
            guard length >= 8, length <= bytes.count - offset else { return nil }
            if Array(bytes[(offset + 4)..<(offset + 8)]) == Array("xml ".utf8) {
                let packet = Data(bytes[(offset + 8)..<(offset + length)])
                let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(packet as CFData))
                return CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
            }
            offset += length
        }
        return nil
    }

    private func writeSource(in directory: URL, labels: [String]) throws -> URL {
        let url = directory.appendingPathComponent(labels.count == 1 ? "metadata.png" : "metadata.tiff")
        let uti = labels.count == 1 ? "public.png" : "public.tiff"
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, uti as CFString,
                                                                        labels.count, nil))
        for label in labels {
            let metadata = CGImageMetadataCreateMutable()
            let namespace = "https://example.com/conv3rt/1.0/" as CFString
            XCTAssertTrue(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, "sample" as CFString, nil))
            let tag = try XCTUnwrap(CGImageMetadataTagCreate(namespace, "sample" as CFString,
                                                            "Label" as CFString, .string, label as CFString))
            XCTAssertTrue(CGImageMetadataSetTagWithPath(metadata, nil, "sample:Label" as CFString, tag))
            XCTAssertTrue(CGImageMetadataSetValueWithPath(metadata, nil, "exif:GPSLatitude" as CFString,
                                                         "41,0N" as CFString))
            let properties: [CFString: Any] = [
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "\(label) comment"],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0,
                                                kCGImagePropertyGPSLatitudeRef: "N"],
            ]
            CGImageDestinationAddImageAndMetadata(destination, Fixtures.rgbaSample(), metadata, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        for (index, label) in labels.enumerated() {
            XCTAssertEqual(try metadataString(at: url, index: index, path: "sample:Label"), label,
                           "The source fixture must contain each page's tag")
        }
        return url
    }
}
