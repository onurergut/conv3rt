import XCTest
@testable import Conv3rtCore

/// Settings that the UI persists should round-trip exactly, so a relaunch
/// restores what the user chose (product requirement: remember the last choice).
final class SettingsTests: XCTestCase {

    func testAlphaBackgroundStorageRoundTrips() {
        let cases: [AlphaBackground] = [
            .white,
            .black,
            .custom(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            .custom(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        for bg in cases {
            XCTAssertEqual(AlphaBackground.fromStorage(bg.storageString), bg,
                           "\(bg) should survive persistence")
        }
    }

    func testAlphaBackgroundStorageFallsBackToWhite() {
        XCTAssertEqual(AlphaBackground.fromStorage(nil), .white)
        XCTAssertEqual(AlphaBackground.fromStorage("nonsense"), .white)
        XCTAssertEqual(AlphaBackground.fromStorage("custom:"), .white)
    }

    func testDefaultSettingsAreLosslessAndKeepMetadata() {
        let s = ConversionSettings()
        XCTAssertEqual(s.mode, .lossless, "Lossless must be the first-run default")
        XCTAssertEqual(s.metadataPolicy, .keep, "Metadata (incl. GPS) is kept by default")
        XCTAssertEqual(s.alphaBackground, .white)
        XCTAssertEqual(s.pdfDPI, 144)
        XCTAssertEqual(s.svgScale, 2.0, accuracy: 0.0001)
        XCTAssertFalse(s.keepFolderStructure)
    }

    func testModeAndPolicyRawValuesAreStable() {
        // Persisted raw values must not change silently between versions.
        XCTAssertEqual(ConversionMode.lossless.rawValue, "lossless")
        XCTAssertEqual(ConversionMode.highestQuality.rawValue, "highestQuality")
        XCTAssertEqual(MetadataPolicy.keep.rawValue, "keep")
        XCTAssertEqual(MetadataPolicy.removeLocation.rawValue, "removeLocation")
        XCTAssertEqual(MetadataPolicy.remove.rawValue, "remove")
    }
}
