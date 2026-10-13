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

    func testWebPIsReadableAndWritableViaBundledCodec() {
        let reg = CapabilityRegistry(probe: RuntimeTypeProbe())
        guard let webp = reg.capability(id: "webp") else {
            return XCTFail("WebP missing from catalog")
        }
        XCTAssertTrue(webp.canRead, "macOS reads WebP via Image I/O")
        // Native Image I/O still cannot write WebP; the bundled libwebp can, so
        // the registry reports it writable — but the raw probe does not.
        XCTAssertTrue(webp.canWrite, "conv3rt writes WebP with the bundled libwebp")
        XCTAssertFalse(RuntimeTypeProbe().canWrite(uti: "org.webmproject.webp"),
                       "Native Image I/O alone still cannot write WebP")
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
