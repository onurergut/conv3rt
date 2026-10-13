import XCTest
import CoreGraphics
@testable import Conv3rtCore

final class DDSTests: XCTestCase {

    private func junk() -> Data {
        Data((0..<160).map { UInt8(($0 * 53 + 7) % 256) })
    }

    func testCanDecodeRejectsJunk() {
        XCTAssertFalse(DDSCodec.canDecode(junk()))
        XCTAssertFalse(DDSCodec.canDecode(Data([0x44, 0x44, 0x53])))
    }

    func testCanDecodeAcceptsRealHeader() throws {
        let data = try DDSCodec.encode(Fixtures.manyColors())
        XCTAssertTrue(DDSCodec.canDecode(data))
        XCTAssertEqual(Array(data.prefix(4)), [0x44, 0x44, 0x53, 0x20])
    }

    func testDecodeRejectsInvalidHeader() {
        XCTAssertThrowsError(try DDSCodec.decode(junk()))
    }

    func testRoundTripOpaqueIsByteIdentical() throws {
        let source = Fixtures.manyColors()
        let decoded = try DDSCodec.decode(try DDSCodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "DDS must round-trip every sample exactly")
    }

    func testRoundTripRGBAIsByteIdentical() throws {
        let source = Fixtures.rgbaSample()
        let decoded = try DDSCodec.decode(try DDSCodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.bytes, b.bytes)
    }

    func testDecodeHandBuiltUncompressedHeader() throws {
        let decoded = try DDSCodec.decode(handBuiltBGRA(width: 2, height: 2))

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        let out = try RGBABuffer.tightlyPacked(from: decoded).bytes
        XCTAssertEqual(out, [
            30, 20, 10, 255,
            60, 50, 40, 128,
            90, 80, 70, 0,
            120, 110, 100, 255,
        ])
    }

    private func handBuiltBGRA(width w: Int, height h: Int) -> Data {
        var header = [UInt8](repeating: 0, count: 128)
        header[0] = 0x44; header[1] = 0x44; header[2] = 0x53; header[3] = 0x20
        putLE(&header, 4, 124)
        putLE(&header, 8, 0x1 | 0x2 | 0x4 | 0x8 | 0x1000)
        putLE(&header, 12, UInt32(h))
        putLE(&header, 16, UInt32(w))
        putLE(&header, 20, UInt32(w * 4))
        putLE(&header, 76, 32)
        putLE(&header, 80, 0x41)
        putLE(&header, 88, 32)
        putLE(&header, 92, 0x00FF_0000)
        putLE(&header, 96, 0x0000_FF00)
        putLE(&header, 100, 0x0000_00FF)
        putLE(&header, 104, 0xFF00_0000)
        putLE(&header, 108, 0x1000)

        let pixels: [UInt8] = [
            10, 20, 30, 255,
            40, 50, 60, 128,
            70, 80, 90, 0,
            100, 110, 120, 255,
        ]
        return Data(header + pixels)
    }

    private func putLE(_ out: inout [UInt8], _ o: Int, _ v: UInt32) {
        out[o] = UInt8(v & 0xFF)
        out[o + 1] = UInt8((v >> 8) & 0xFF)
        out[o + 2] = UInt8((v >> 16) & 0xFF)
        out[o + 3] = UInt8((v >> 24) & 0xFF)
    }
}
