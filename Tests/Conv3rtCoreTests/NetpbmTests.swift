import XCTest
import CoreGraphics
@testable import Conv3rtCore

/// Verifies the native Netpbm reader/writer, with PFM (Portable Float Map)
/// as the primary target since macOS Image I/O does not read it.
final class NetpbmTests: XCTestCase {

    // MARK: - Magic sniffing

    func testCanDecodeEachMagic() {
        for magic in ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "PF", "Pf"] {
            XCTAssertTrue(NetpbmCodec.canDecode(Data((magic + "\n1 1\n").utf8)), magic)
        }
    }

    func testCanDecodeRejectsNonNetpbm() {
        XCTAssertFalse(NetpbmCodec.canDecode(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])))
        XCTAssertFalse(NetpbmCodec.canDecode(Data("GIF89a".utf8)))
        XCTAssertFalse(NetpbmCodec.canDecode(Data("P8\n".utf8)))
        XCTAssertFalse(NetpbmCodec.canDecode(Data([0x50])))
        XCTAssertFalse(NetpbmCodec.canDecode(Data()))
    }

    // MARK: - PPM (P6)

    func testPPMRoundTripIsExact() throws {
        let source = Fixtures.manyColors()
        let data = try NetpbmCodec.encode(source)
        XCTAssertEqual(String(decoding: [UInt8](data.prefix(2)), as: UTF8.self), "P6")

        let decoded = try NetpbmCodec.decode(data)
        let a = try Fixtures.rgbaBytes(of: source)
        let b = try Fixtures.rgbaBytes(of: decoded)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "8-bit PPM must round-trip exactly")
    }

    func testDecodeBinaryPPM() throws {
        var data = Data("P6\n2 1\n255\n".utf8)
        data.append(contentsOf: [255, 0, 0, 0, 255, 0])
        let decoded = try NetpbmCodec.decode(data)
        let rgba = try Fixtures.rgbaBytes(of: decoded)
        XCTAssertEqual(rgba.width, 2)
        XCTAssertEqual(rgba.bytes, [255, 0, 0, 255, 0, 255, 0, 255])
    }

    // MARK: - PGM (P5)

    func testPGMRoundTripIsExact() throws {
        let source = try gray8(width: 8, height: 8)
        let data = try NetpbmCodec.encode(source)
        XCTAssertEqual(String(decoding: [UInt8](data.prefix(2)), as: UTF8.self), "P5")

        let decoded = try NetpbmCodec.decode(data)
        let a = try Fixtures.rgbaBytes(of: source)
        let b = try Fixtures.rgbaBytes(of: decoded)
        XCTAssertEqual(a.bytes, b.bytes, "8-bit PGM must round-trip exactly")
    }

    func testDecodeASCIIPPM() throws {
        let text = "P3\n# a comment\n2 1\n255\n255 0 0  0 255 0\n"
        let decoded = try NetpbmCodec.decode(Data(text.utf8))
        let rgba = try Fixtures.rgbaBytes(of: decoded)
        XCTAssertEqual(rgba.width, 2)
        XCTAssertEqual(rgba.bytes, [255, 0, 0, 255, 0, 255, 0, 255])
    }

    // MARK: - 16-bit PGM

    func testSixteenBitPGMRoundTrip() throws {
        let width = 6, height = 4
        let source = try gray16(width: width, height: height)
        let data = try NetpbmCodec.encode(source)
        XCTAssertEqual(String(decoding: [UInt8](data.prefix(2)), as: UTF8.self), "P5")
        XCTAssertTrue(String(decoding: data.prefix(64), as: UTF8.self).contains("65535"),
                      "16-bit PGM must declare maxval 65535")

        let decoded = try NetpbmCodec.decode(data)
        XCTAssertEqual(decoded.bitsPerComponent, 16)

        let words = try littleEndianWords(of: decoded)
        for i in 0..<(width * height) {
            let expected = UInt16((i * 257) % 65536)
            XCTAssertEqual(words[i * 3], expected, "16-bit gray must survive at full precision")
            XCTAssertEqual(words[i * 3 + 1], expected)
            XCTAssertEqual(words[i * 3 + 2], expected)
        }
    }

    // MARK: - PFM (PF / Pf)

    func testPFMColorRoundTrip() throws {
        let width = 5, height = 3
        let source = try floatColor(width: width, height: height)
        let data = try NetpbmCodec.encode(source)
        XCTAssertEqual(String(decoding: [UInt8](data.prefix(2)), as: UTF8.self), "PF")

        let decoded = try NetpbmCodec.decode(data)
        let samples = try floatRGBA(of: decoded)
        for i in 0..<(width * height) {
            let expected = floatPattern(i)
            XCTAssertEqual(Double(samples[i * 4]), Double(expected.r), accuracy: 1e-5)
            XCTAssertEqual(Double(samples[i * 4 + 1]), Double(expected.g), accuracy: 1e-5)
            XCTAssertEqual(Double(samples[i * 4 + 2]), Double(expected.b), accuracy: 1e-5)
        }
    }

    func testPFMHeaderUsesNegativeScale() throws {
        let data = try NetpbmCodec.encode(try floatColor(width: 2, height: 2))
        XCTAssertTrue(String(decoding: data.prefix(32), as: UTF8.self).contains("-1.0"),
                      "PFM must advertise little-endian via a negative scale")
    }

    // MARK: - Errors

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try NetpbmCodec.decode(Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertThrowsError(try NetpbmCodec.decode(Data("P6\n2 1\n99999\n".utf8)))
        XCTAssertThrowsError(try NetpbmCodec.decode(Data("P6\n2 1\n255\n".utf8)),
                             "Truncated raster data must be rejected")
    }

    func testErrorDescriptions() {
        XCTAssertEqual(NetpbmError.notNetpbm.localizedDescription,
                       "The data is not a Netpbm image.")
        XCTAssertEqual(NetpbmError.unsupported("x").localizedDescription,
                       "This Netpbm variant is not supported. x")
    }

    // MARK: - Fixtures

    private func gray8(width: Int, height: Int) throws -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: width * height)
        for i in 0..<(width * height) { buf[i] = UInt8((i * 13 + 7) % 256) }
        return ctx.makeImage()!
    }

    private func gray16(width: Int, height: Int) throws -> CGImage {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).union(.byteOrder16Little)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16,
                            bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: info.rawValue)!
        let buf = ctx.data!.bindMemory(to: UInt16.self, capacity: width * height)
        for i in 0..<(width * height) { buf[i] = UInt16((i * 257) % 65536) }
        return ctx.makeImage()!
    }

    private func floatPattern(_ i: Int) -> (r: Float, g: Float, b: Float) {
        (Float(i) / 100, Float((i * 2) % 50) / 100, Float((i * 3) % 100) / 100)
    }

    private func floatColor(width: Int, height: Int) throws -> CGImage {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.floatComponents).union(.byteOrder32Little)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 32,
                            bytesPerRow: width * 16, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: info.rawValue)!
        let buf = ctx.data!.bindMemory(to: Float.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let p = floatPattern(i)
            buf[i * 4] = p.r; buf[i * 4 + 1] = p.g; buf[i * 4 + 2] = p.b; buf[i * 4 + 3] = 1
        }
        return ctx.makeImage()!
    }

    private func floatRGBA(of image: CGImage) throws -> [Float] {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.floatComponents).union(.byteOrder32Little)
        var out = [Float](repeating: 0, count: image.width * image.height * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                bitsPerComponent: 32, bytesPerRow: image.width * 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: info.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return out
    }

    private func littleEndianWords(of image: CGImage) throws -> [UInt16] {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            throw NetpbmError.malformed("No provider data.")
        }
        let count = image.width * image.height * 3
        var words = [UInt16](repeating: 0, count: count)
        for i in 0..<count { words[i] = UInt16(ptr[i * 2]) | UInt16(ptr[i * 2 + 1]) << 8 }
        return words
    }
}
