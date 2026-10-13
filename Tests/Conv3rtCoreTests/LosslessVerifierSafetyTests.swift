import XCTest
import CoreGraphics
@testable import Conv3rtCore

final class LosslessVerifierSafetyTests: XCTestCase {
    func testIdenticalPFMNaNPayloadsAreLossless() throws {
        let directory = TempDir()
        for word: UInt32 in [0x7FC0_0011, 0x7F80_0011, 0xFFC0_0011] {
            let data = pfm(word: word)
            let image = try NetpbmCodec.decode(data)
            let output = directory.url.appendingPathComponent("same-\(word).pfm")
            try data.write(to: output)
            XCTAssertNoThrow(try verify(image, output: output))
        }
    }

    func testDifferentPFMNaNPayloadsAreRejected() throws {
        let directory = TempDir()
        let source = try NetpbmCodec.decode(pfm(word: 0x7FC0_0011))
        for word: UInt32 in [0x7FC0_0012, 0x7F80_0011, 0xFFC0_0011, 0x3F80_0000] {
            let output = directory.url.appendingPathComponent("different-\(word).pfm")
            try pfm(word: word).write(to: output)
            XCTAssertThrowsError(try verify(source, output: output))
        }
    }

    func testDifferentFiniteFloatSamplesAreRejected() throws {
        let directory = TempDir()
        let source = try NetpbmCodec.decode(pfm(word: 0x3F80_0000))
        let output = directory.url.appendingPathComponent("changed.pfm")
        try pfm(word: 0x3F80_0001).write(to: output)
        XCTAssertThrowsError(try verify(source, output: output))
    }

    func testPromotedFloat16NaNPayloadIsPreserved() throws {
        let directory = TempDir()
        let provider = try XCTUnwrap(CGDataProvider(data: Data([0x01, 0x7E, 0x01, 0x7E, 0x01, 0x7E, 0, 0x3C]) as CFData))
        let source = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 64,
                                          bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                                             .union(.floatComponents).union(.byteOrder16Little),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let preserved = directory.url.appendingPathComponent("promoted.pfm")
        // Binary16 0x7E01 becomes binary32 0x7FC02000 with its payload intact.
        try pfm(word: 0x7FC0_2000).write(to: preserved)
        XCTAssertNoThrow(try verify(source, output: preserved))
        let changed = directory.url.appendingPathComponent("changed-promotion.pfm")
        try pfm(word: 0x7FC0_4000).write(to: changed)
        XCTAssertThrowsError(try verify(source, output: changed))
    }

    func testSixteenBitGraySamplesMatchAcrossDeclaredByteOrders() throws {
        let directory = TempDir()
        let provider = try XCTUnwrap(CGDataProvider(data: Data([0x12, 0x34]) as CFData))
        let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 16,
                                         bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                                            .union(.byteOrder16Big), provider: provider,
                                         decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = try Fixtures.write(image, uti: "public.png", ext: "png", directory: directory.url)
        XCTAssertNoThrow(try verify(image, output: output))
    }

    func testSubByteIndexedPaletteMatchesExpandedRGBSamples() throws {
        let directory = TempDir()
        let base = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let palette: [UInt8] = [255, 0, 0, 0, 255, 0]
        let indexed = try palette.withUnsafeBufferPointer {
            try XCTUnwrap(CGColorSpace(indexedBaseSpace: base, last: 1, colorTable: $0.baseAddress!))
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data([0b0100_0000]) as CFData))
        let source = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 1, bitsPerPixel: 1,
                                          bytesPerRow: 1, space: indexed,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let expanded = Fixtures.nonPremultiplied(rawRGBA: [255, 0, 0, 255, 0, 255, 0, 255], width: 2, height: 1)
        let output = try Fixtures.write(expanded, uti: "public.png", ext: "png", directory: directory.url)
        XCTAssertNoThrow(try verify(source, output: output))
    }

    private func pfm(word: UInt32) -> Data {
        var data = Data("Pf\n1 1\n-1\n".utf8)
        data.append(contentsOf: [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8),
                                 UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)])
        return data
    }

    private func verify(_ image: CGImage, output: URL) throws {
        let info = ImageInfo(url: output, detectedUTI: nil, declaredUTI: nil, fileSize: 0,
                             pixelWidth: image.width, pixelHeight: image.height, frameCount: 1, pageCount: 1,
                             frameDurations: [], loopCount: nil, canvasWidth: image.width, canvasHeight: image.height,
                             bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
                             hasAlpha: false, colorModel: nil, colorSpaceName: nil, hasColorProfile: false,
                             exifOrientation: nil, hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false)
        try LosslessVerifier().verify(sourceProvider: StaticImageProvider(image: image), sourceInfo: info,
                                      sourceIndices: [0], outputURL: output, expectedOutputFrames: 1)
    }
}
