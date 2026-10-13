import XCTest
@testable import Conv3rtCore

final class OutputSafetyTests: XCTestCase {
    func testMissingTemporaryFileDoesNotConsumeCollisionNames() throws {
        let directory = TempDir()
        let safe = try SafeOutput(directory: directory.url)
        let namer = OutputNamer()
        let first = namer.uniqueURL(in: directory.url, baseName: "result", fileExtension: "png")
        XCTAssertThrowsError(try safe.commit(to: first, namer: namer, baseName: "result", ext: "png"))
        let next = namer.uniqueURL(in: directory.url, baseName: "result", fileExtension: "png")
        XCTAssertEqual(next.lastPathComponent, "result-1.png",
                       "A missing source is not a destination collision and must not retry")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
    }

    func testDanglingSymlinkIsAnOccupiedOutputName() throws {
        let directory = TempDir()
        let occupied = directory.url.appendingPathComponent("result.png")
        let missing = directory.url.appendingPathComponent("missing.png")
        try FileManager.default.createSymbolicLink(at: occupied, withDestinationURL: missing)
        let next = OutputNamer().uniqueURL(in: directory.url, baseName: "result", fileExtension: "png")
        XCTAssertEqual(next.lastPathComponent, "result-1.png")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: occupied.path), missing.path)
    }

    func testCollisionPreservesExistingFileAndCommitsCompletePayload() throws {
        let directory = TempDir()
        let safe = try SafeOutput(directory: directory.url)
        defer { safe.cleanup() }
        let destination = directory.url.appendingPathComponent("result.png")
        let existing = Data("existing output".utf8)
        let payload = Data("verified new output".utf8)
        try existing.write(to: destination)
        try payload.write(to: safe.tempURL)
        let placed = try safe.commit(to: destination, namer: OutputNamer(), baseName: "result", ext: "png")
        XCTAssertEqual(placed.lastPathComponent, "result-1.png")
        XCTAssertEqual(try Data(contentsOf: destination), existing)
        XCTAssertEqual(try Data(contentsOf: placed), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: safe.tempURL.path))
    }

    func testConcurrentCommitsPreserveEveryPayloadWithoutOverwriting() throws {
        let directory = TempDir()
        let destination = directory.url.appendingPathComponent("result.bin")
        let namer = OutputNamer()
        let lock = NSLock()
        var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                let safe = try SafeOutput(directory: directory.url)
                defer { safe.cleanup() }
                try Data("payload \(index)".utf8).write(to: safe.tempURL)
                _ = try safe.commit(to: destination, namer: namer, baseName: "result", ext: "bin")
            } catch {
                lock.lock(); errors.append(error.localizedDescription); lock.unlock()
            }
        }
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        let files = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        let payloads = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(Set(payloads), Set((0..<40).map { "payload \($0)" }))
        XCTAssertEqual(files.count, 40)
    }
}
