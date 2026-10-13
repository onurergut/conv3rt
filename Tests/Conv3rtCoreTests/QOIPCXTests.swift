import XCTest
import CoreGraphics
@testable import Conv3rtCore

final class QOIPCXTests: XCTestCase {

    private func junk() -> Data {
        Data((0..<64).map { UInt8(($0 * 37 + 11) % 256) })
    }

    // MARK: - QOI

    func testQOICanDecodeRejectsJunk() {
        XCTAssertFalse(QOICodec.canDecode(junk()))
        XCTAssertFalse(QOICodec.canDecode(Data([0x71, 0x6F, 0x69])))
    }

    func testQOICanDecodeAcceptsRealHeader() throws {
        let data = try QOICodec.encode(Fixtures.rgbaSample())
        XCTAssertTrue(QOICodec.canDecode(data))
        XCTAssertEqual(Array(data.prefix(4)), [0x71, 0x6F, 0x69, 0x66])
    }

    func testQOIDecodeRejectsInvalidHeader() {
        XCTAssertThrowsError(try QOICodec.decode(junk()))
    }

    func testQOIRoundTripOpaqueIsByteIdentical() throws {
        let source = Fixtures.manyColors()
        let decoded = try QOICodec.decode(try QOICodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "QOI must round-trip every sample exactly")
    }

    func testQOIRoundTripRGBAIsByteIdentical() throws {
        let source = Fixtures.rgbaSample()
        let decoded = try QOICodec.decode(try QOICodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.bytes, b.bytes)
    }

    func testQOIRoundTripPreservesTransparency() throws {
        let source = Fixtures.transparentRGBSample()
        let decoded = try QOICodec.decode(try QOICodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.bytes, b.bytes)
        // Pixel 2 is fully transparent and carries RGB (30,30,30).
        XCTAssertEqual(b.bytes[8], 30)
        XCTAssertEqual(b.bytes[9], 30)
        XCTAssertEqual(b.bytes[10], 30)
        XCTAssertEqual(b.bytes[11], 0)
    }

    // MARK: - PCX

    func testPCXCanDecodeRejectsJunk() {
        XCTAssertFalse(PCXCodec.canDecode(junk()))
        XCTAssertFalse(PCXCodec.canDecode(Data([0x0A, 5, 1, 8])))
    }

    func testPCXCanDecodeAcceptsRealHeader() throws {
        let data = try PCXCodec.encode(Fixtures.manyColors())
        XCTAssertTrue(PCXCodec.canDecode(data))
        XCTAssertEqual(data[0], 0x0A)
        XCTAssertEqual(data[2], 1)
    }

    func testPCXDecodeRejectsInvalidHeader() {
        XCTAssertThrowsError(try PCXCodec.decode(junk()))
    }

    func testPCXRoundTripOpaqueIsByteIdentical() throws {
        let source = Fixtures.manyColors()
        let decoded = try PCXCodec.decode(try PCXCodec.encode(source))
        let a = try RGBABuffer.tightlyPacked(from: source)
        let b = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "PCX must round-trip every RGB sample exactly")
    }

    func testPCXDecodesIndexedWithPalette() throws {
        let data = indexedPCX()
        XCTAssertTrue(PCXCodec.canDecode(data))
        let decoded = try PCXCodec.decode(data)
        let out = try RGBABuffer.tightlyPacked(from: decoded)
        XCTAssertEqual(out.width, 4)
        XCTAssertEqual(out.height, 2)
        // Row 0 indices are 0,1,2,3 and row 1 indices are 3,2,1,0.
        for x in 0..<4 {
            assertPalette(out.bytes, pixel: x, index: x)
            assertPalette(out.bytes, pixel: 4 + x, index: 3 - x)
        }
    }

    private func assertPalette(_ bytes: [UInt8], pixel: Int, index: Int) {
        XCTAssertEqual(bytes[pixel * 4], UInt8(index * 10))
        XCTAssertEqual(bytes[pixel * 4 + 1], UInt8(index * 20))
        XCTAssertEqual(bytes[pixel * 4 + 2], UInt8(index * 30))
        XCTAssertEqual(bytes[pixel * 4 + 3], 255)
    }

    private func indexedPCX() -> Data {
        let width = 4, height = 2
        var header = [UInt8](repeating: 0, count: 128)
        header[0] = 0x0A
        header[1] = 5
        header[2] = 1
        header[3] = 8
        header[8] = UInt8(width - 1)
        header[10] = UInt8(height - 1)
        header[65] = 1
        header[66] = UInt8(width)
        header[68] = 1

        var palette = [UInt8](repeating: 0, count: 769)
        palette[0] = 0x0C
        for i in 0..<256 {
            palette[1 + i * 3] = UInt8(i * 10 % 256)
            palette[2 + i * 3] = UInt8(i * 20 % 256)
            palette[3 + i * 3] = UInt8(i * 30 % 256)
        }

        let indices: [UInt8] = [0, 1, 2, 3, 3, 2, 1, 0]
        return Data(header + indices + palette)
    }
}
