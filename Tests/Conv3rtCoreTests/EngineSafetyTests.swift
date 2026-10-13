import XCTest
@testable import Conv3rtCore

final class EngineSafetyTests: XCTestCase {
    func testCanceledSplitRollsBackCommittedFrames() throws {
        let source = TempDir(), output = TempDir()
        let url = try Fixtures.multipageTIFF(directory: source.url, pages: 3)
        let target = try XCTUnwrap(CapabilityRegistry.shared.capability(id: "png"))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url), target: target,
                                            settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        let token = CancelToken()
        XCTAssertThrowsError(try ConversionEngine().convert(
            plan: plan, outputDirectory: output.url, namer: OutputNamer(), target: target,
            isCancelled: { token.isCancelled }, progress: { fraction in
                if fraction > 0 { token.cancel() }
            })) { error in
                XCTAssertEqual(error as? ConversionError, .canceled)
            }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.url.path).isEmpty)
    }

    func testFailedSplitRollsBackOnlyItsOwnOutputs() throws {
        let source = TempDir(), output = TempDir()
        let url = try Fixtures.multipageTIFF(directory: source.url, pages: 3)
        let unrelated = output.url.appendingPathComponent("existing.png")
        let contents = Data("existing file".utf8)
        try contents.write(to: unrelated)
        let target = try XCTUnwrap(CapabilityRegistry.shared.capability(id: "png"))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url), target: target,
                                            settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        let token = CancelToken()
        XCTAssertThrowsError(try ConversionEngine().convert(
            plan: plan, outputDirectory: output.url, namer: OutputNamer(), target: target,
            isCancelled: { token.isCancelled }, progress: { fraction in
                if fraction > 0 { token.cancel() }
            }))
        XCTAssertEqual(try Data(contentsOf: unrelated), contents)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.url.path), ["existing.png"])
    }

    func testSplitRollbackDoesNotDeleteAReplacementFile() throws {
        let source = TempDir(), output = TempDir()
        let url = try Fixtures.multipageTIFF(directory: source.url, pages: 3)
        let replacement = source.url.appendingPathComponent("replacement")
        let contents = Data("file owned by someone else".utf8)
        try contents.write(to: replacement)
        let firstOutput = output.url.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-page-0001.png")
        let target = try XCTUnwrap(CapabilityRegistry.shared.capability(id: "png"))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url), target: target,
                                            settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        let token = CancelToken()
        XCTAssertThrowsError(try ConversionEngine().convert(
            plan: plan, outputDirectory: output.url, namer: OutputNamer(), target: target,
            isCancelled: { token.isCancelled }, progress: { fraction in
                guard fraction > 0, !token.isCancelled else { return }
                do {
                    try FileManager.default.removeItem(at: firstOutput)
                    try FileManager.default.moveItem(at: replacement, to: firstOutput)
                } catch { XCTFail("Could not replace the first output: \(error)") }
                token.cancel()
            }))
        XCTAssertEqual(try Data(contentsOf: firstOutput), contents)
    }
}
