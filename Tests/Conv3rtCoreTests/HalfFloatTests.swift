import XCTest
@testable import Conv3rtCore

final class HalfFloatTests: XCTestCase {
    func testDecodesKnownValues() {
        XCTAssertEqual(HalfFloat.decode(0x0000), 0)
        XCTAssertEqual(HalfFloat.decode(0x8000).isZero, true)
        XCTAssertTrue(HalfFloat.decode(0x8000).sign == .minus)
        XCTAssertEqual(HalfFloat.decode(0x3C00), 1)
        XCTAssertEqual(HalfFloat.decode(0x3800), 0.5)
        XCTAssertEqual(HalfFloat.decode(0x4000), 2)
        XCTAssertEqual(HalfFloat.decode(0x0001), 0x1p-24)
        XCTAssertEqual(HalfFloat.decode(0x03FF), 1023 * pow(2, -24))
        XCTAssertEqual(HalfFloat.decode(0x7BFF), 65504)
        XCTAssertEqual(HalfFloat.decode(0x7C00), .infinity)
        XCTAssertEqual(HalfFloat.decode(0xFC00), -.infinity)
        XCTAssertTrue(HalfFloat.decode(0x7E00).isNaN)
        XCTAssertTrue(HalfFloat.decode(0xFE00).isNaN)
    }

    #if arch(arm64)
    func testMatchesFloat16ForEveryFinitePattern() {
        for bits in UInt16(0)...UInt16(0x7BFF) {
            let expected = Double(Float16(bitPattern: bits))
            let actual = HalfFloat.decode(bits)
            XCTAssertEqual(actual, expected, "mismatch at 0x\(String(bits, radix: 16))")
        }
        for bits in UInt16(0x8000)...UInt16(0xFBFF) {
            XCTAssertEqual(HalfFloat.decode(bits), Double(Float16(bitPattern: bits)),
                           "mismatch at 0x\(String(bits, radix: 16))")
        }
    }
    #endif
}
