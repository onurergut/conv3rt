import XCTest
@testable import Conv3rtCore

final class ScannerTests: XCTestCase {
    func testFolderReportsCorruptKnownImagesButIgnoresOrdinaryDocuments() throws {
        let directory = TempDir()
        let corrupt = directory.url.appendingPathComponent("corrupt.png")
        let document = directory.url.appendingPathComponent("notes.txt")
        try Data("Not an image".utf8).write(to: corrupt)
        try Data("Ordinary notes".utf8).write(to: document)
        let result = FolderScanner().scan(urls: [directory.url])
        XCTAssertTrue(result.imageFiles.isEmpty)
        XCTAssertEqual(result.skipped.map { $0.resolvingSymlinksInPath() }, [corrupt.resolvingSymlinksInPath()])
    }

    func testMissingExplicitInputIsReported() {
        let missing = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).png")
        let result = FolderScanner().scan(urls: [missing])
        XCTAssertEqual(result.skipped, [missing])
    }

    func testUnreadableFolderIsReported() throws {
        let directory = TempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.url.path) }
        let result = FolderScanner().scan(urls: [directory.url])
        XCTAssertEqual(result.skipped, [directory.url])
    }

    func testFolderDetectsMisnamedImageByContent() throws {
        let directory = TempDir()
        let image = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "txt",
                                       directory: directory.url)
        let result = FolderScanner().scan(urls: [directory.url])
        XCTAssertEqual(result.imageFiles.map { $0.resolvingSymlinksInPath() }, [image.resolvingSymlinksInPath()])
        XCTAssertTrue(result.skipped.isEmpty)
    }

    func testOverlappingImportsDeduplicateTheSameFile() throws {
        let directory = TempDir()
        let image = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                       directory: directory.url)
        let alias = directory.url.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: image)
        let result = FolderScanner().scan(urls: [image, directory.url, alias])
        XCTAssertEqual(result.imageFiles, [image])
    }

    func testCaseDistinctImagePathsAreBothImportedWhenFilesystemSupportsThem() throws {
        let directory = TempDir()
        let lower = directory.url.appendingPathComponent("case.png")
        let upper = directory.url.appendingPathComponent("CASE.png")
        let fixture = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                         directory: directory.url)
        try FileManager.default.copyItem(at: fixture, to: lower)
        guard !FileManager.default.fileExists(atPath: upper.path) else {
            throw XCTSkip("This filesystem does not support case-distinct filenames")
        }
        try FileManager.default.copyItem(at: fixture, to: upper)
        let result = FolderScanner().scan(urls: [lower, upper])
        XCTAssertEqual(Set(result.imageFiles), Set([lower, upper]))
    }
}
