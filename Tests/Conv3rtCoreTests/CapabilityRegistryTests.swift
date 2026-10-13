import XCTest
@testable import Conv3rtCore

final class CapabilityRegistryTests: XCTestCase {

    func testPNGIsReadableAndWritable() {
        let reg = CapabilityRegistry(probe: RuntimeTypeProbe())
        guard let png = reg.capability(id: "png") else {
            return XCTFail("PNG missing from catalog")
        }
        XCTAssertTrue(png.canRead, "PNG should be readable on macOS")
        XCTAssertTrue(png.canWrite, "PNG should be writable on macOS")
    }

    func testWebPReadableButNotNativelyWritable() {
        let reg = CapabilityRegistry(probe: RuntimeTypeProbe())
        guard let webp = reg.capability(id: "webp") else {
            return XCTFail("WebP missing from catalog")
        }
        // This documents the real macOS behavior this project is built around.
        XCTAssertTrue(webp.canRead, "macOS reads WebP via Image I/O")
        XCTAssertFalse(webp.canWrite, "macOS does not write WebP via Image I/O")
    }

    func testRuntimeTypesWithoutCatalogEntryAreSurfaced() {
        let reg = CapabilityRegistry(probe: RuntimeTypeProbe())
        let runtimeOnly = reg.capabilities().filter { $0.id.hasPrefix("runtime.") }
        // There is always some runtime type not in our hand-authored table.
        XCTAssertFalse(runtimeOnly.isEmpty)
    }

    func testWritableListIsNonEmptyAndSorted() {
        let reg = CapabilityRegistry(probe: RuntimeTypeProbe())
        let w = reg.writableFormats()
        XCTAssertFalse(w.isEmpty)
        XCTAssertEqual(w.map(\.displayName), w.map(\.displayName).sorted())
    }
}
