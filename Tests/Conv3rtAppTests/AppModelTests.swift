import XCTest
import Combine
import ImageIO
import AppKit
@testable import Conv3rtApp
import Conv3rtCore

final class AppModelTests: XCTestCase {
    private let defaultsName = "conv3rt-app-tests-\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        super.tearDown()
    }

    @MainActor
    private func makeModel() -> AppModel {
        AppModel(defaults: UserDefaults(suiteName: defaultsName)!)
    }

    @MainActor
    func testImportedPNGNotifiesWhenConversionBecomesReady() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePNG(in: directory)
        let model = makeModel()
        let ready = expectation(description: "The window is notified when the imported PNG is ready")
        var notified = false
        let subscription = model.objectWillChange.sink {
            Task { @MainActor in
                if model.convertibleCount == 1 && !notified {
                    notified = true
                    ready.fulfill()
                }
            }
        }
        model.addFiles([source])
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(model.convertibleCount, 1)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testChangingOutputFormatReplansReadyPNG() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory))
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.selectedFormatID = "png"
        model.recomputePlans()
        XCTAssertEqual(model.convertibleCount, 1)
        model.selectedFormatID = "jpeg"
        XCTAssertEqual(model.convertibleCount, 0, "JPEG must block this lossless PNG conversion")
        XCTAssertEqual(item.plan?.codecId, "jpeg")
    }

    @MainActor
    func testRowProgressAndCompletionNotifyTheWindow() throws {
        let model = makeModel()
        let item = ImportItem(url: URL(fileURLWithPath: "/tmp/progress.png"))
        model.items = [item]
        var notifications = 0
        let subscription = model.objectWillChange.sink { notifications += 1 }
        item.state = .running(0.5)
        XCTAssertGreaterThan(notifications, 0, "Row progress must refresh the window")
        XCTAssertEqual(item.statusText, "Converting 50%")
        notifications = 0
        item.state = .succeeded(outputs: [URL(fileURLWithPath: "/tmp/result.png")], notes: [])
        XCTAssertGreaterThan(notifications, 0, "Completion must refresh the row and its actions")
        XCTAssertEqual(item.statusText, "Done")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testRemovedItemsStopNotifyingTheWindow() {
        let model = makeModel()
        let item = ImportItem(url: URL(fileURLWithPath: "/tmp/removed.png"))
        model.items = [item]
        model.remove(item)
        var notifications = 0
        let subscription = model.objectWillChange.sink { notifications += 1 }
        item.state = .running(0.5)
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testReadyPNGConversionCompletesWithMatchingRowAndOutput() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePNG(in: directory)
        let item = ImportItem(url: source)
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "App consumes the queue's terminal event")
        let subscription = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startConversion()
        XCTAssertTrue(model.isRunning)
        await fulfillment(of: [finished], timeout: 3)
        model.cancel()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.progress, 1)
        guard case .succeeded(let outputs, _) = item.state else {
            return XCTFail("Expected a successful row, got \(item.state)")
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertNotEqual(outputs[0], source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[0].path))
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testRetryFailedPreservesSuccessfulOutputAndRetriesOnlyFailedRow() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let successful = ImportItem(url: try writePNG(in: directory, name: "successful"))
        let failed = ImportItem(url: try writePNG(in: directory, name: "failed"))
        await successful.load()
        await failed.load()
        let previousOutput = directory.appendingPathComponent("previous.png")
        successful.state = .succeeded(outputs: [previousOutput], notes: [])
        failed.state = .failed(message: "Temporary failure")
        let model = makeModel()
        model.items = [successful, failed]
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "Retry completes")
        let subscription = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.retryFailed()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(successful.resultURLs, [previousOutput], "Retry must keep the successful row's original result")
        XCTAssertEqual(failed.resultURLs.count, 1)
        XCTAssertEqual(model.statusLine, "Finished: 1 succeeded, 0 failed.")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testRunningBatchRejectsRemovalClearAndAdditionalImports() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory))
        let extra = try writePNG(in: directory, name: "extra")
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "Batch completes")
        let subscription = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startConversion()
        model.remove(item)
        model.clearAll()
        model.addFiles([extra])
        XCTAssertEqual(model.items.map(\.id), [item.id])
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(item.resultURLs.count, 1)
        XCTAssertEqual(model.statusLine, "Finished: 1 succeeded, 0 failed.")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testFinishedSummaryUsesTheBatchSnapshot() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory))
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "Detached batch completes")
        let subscription = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startConversion()
        model.items = []
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(item.resultURLs.count, 1)
        XCTAssertEqual(model.statusLine, "Finished: 1 succeeded, 0 failed.")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testImmediateCancelReportsCanceledWithoutCompleteProgress() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory))
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "Cancellation completes")
        let subscription = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.startConversion()
        model.cancel()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(item.state, .canceled)
        XCTAssertEqual(model.progress, 0)
        XCTAssertTrue(model.statusLine.contains("1 canceled"))
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testWebPConversionShowsIntermediateProgressAndCompletes() async throws {
        _ = NSApplication.shared
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory))
        await item.load()
        let model = makeModel()
        model.items = [item]
        model.selectedFormatID = "webp"
        model.outputDirectory = directory
        model.recomputePlans()
        let finished = expectation(description: "WebP conversion completes")
        let completion = model.$isRunning.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        var intermediateProgress = false
        var prematureCompletion = false
        let progress = model.$progress.sink { value in
            if value > 0 && value < 1 { intermediateProgress = true }
            if value == 1 && item.resultURLs.isEmpty { prematureCompletion = true }
        }
        model.startConversion()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(intermediateProgress, "One image must show encode progress")
        XCTAssertFalse(prematureCompletion, "100% requires a committed output")
        XCTAssertEqual(item.resultURLs.first?.pathExtension, "webp")
        XCTAssertEqual(model.progress, 1)
        withExtendedLifetime((completion, progress)) {}
    }

    @MainActor
    func testAddingAnotherFileDoesNotReinspectReadyRows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePNG(in: directory)
        let model = makeModel()
        let firstReady = expectation(description: "First import is ready")
        var firstNotified = false
        let firstSubscription = model.objectWillChange.sink {
            Task { @MainActor in
                if model.convertibleCount == 1 && !firstNotified {
                    firstNotified = true
                    firstReady.fulfill()
                }
            }
        }
        model.addFiles([source])
        await fulfillment(of: [firstReady], timeout: 3)
        let first = try XCTUnwrap(model.items.first)
        try FileManager.default.removeItem(at: source)
        let extra = try writePNG(in: directory, name: "extra")
        let secondReady = expectation(description: "Second import is inspected")
        var secondNotified = false
        let secondSubscription = model.objectWillChange.sink {
            Task { @MainActor in
                if model.items.contains(where: { $0.url == extra && $0.info != nil }) && !secondNotified {
                    secondNotified = true
                    secondReady.fulfill()
                }
            }
        }
        model.addFiles([extra])
        await fulfillment(of: [secondReady], timeout: 3)
        XCTAssertNotNil(first.info)
        XCTAssertNil(first.loadError, "Adding another file must not reload previously inspected rows")
        withExtendedLifetime((firstSubscription, secondSubscription)) {}
    }

    @MainActor
    func testPendingRowDisclosesReadinessAndInspectionFailure() async throws {
        let item = ImportItem(url: URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).png"))
        XCTAssertNotEqual(item.statusText, "—")
        await item.load()
        XCTAssertNotNil(item.loadError)
        XCTAssertTrue(item.statusText.hasPrefix("Failed:"))
    }

    @MainActor
    func testOverlappingLoadsBothWaitForTheSameInspection() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ImportItem(url: try writePNG(in: directory, width: 2048))
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    await item.load()
                    return await item.info != nil
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results, [true, true], "Every caller must await inspection readiness")
    }

    @MainActor
    func testClearPendingImportDoesNotRestoreRowsOrOverwriteNewImport() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try writePNG(in: directory, name: "old")
        let replacement = try writePNG(in: directory, name: "replacement")
        let model = makeModel()
        model.addFiles([old])
        model.clearAll()
        let finished = expectation(description: "Replacement import finishes")
        let subscription = model.$isImporting.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.addFiles([replacement])
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(model.items.map(\.url), [replacement])
        XCTAssertEqual(model.convertibleCount, 1)
        XCTAssertTrue(model.statusLine.contains("Added 1"))
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testOverlappingImportsDoNotDuplicateRows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePNG(in: directory)
        let model = makeModel()
        let finished = expectation(description: "Overlapping imports finish")
        let subscription = model.$isImporting.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.addFiles([source])
        model.addFiles([directory])
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.convertibleCount, 1)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testSeparateImportsOfTheSameFileIdentityDoNotDuplicateRows() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try writePNG(in: directory)
        let alias = directory.appendingPathComponent("same-file.png")
        try FileManager.default.linkItem(at: source, to: alias)
        let model = makeModel()
        let finished = expectation(description: "Alias imports finish")
        let subscription = model.$isImporting.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        model.addFiles([source])
        model.addFiles([alias])
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(model.items.count, 1, "One source file must not be queued twice through aliases")
        XCTAssertEqual(model.convertibleCount, 1)
        withExtendedLifetime(subscription) {}
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conv3rt-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(in directory: URL, name: String = "source", width: Int = 8) throws -> URL {
        let source = directory.appendingPathComponent("\(name).png")
        let image = try XCTUnwrap(CGContext(data: nil, width: width, height: width, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
                                                                       "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return source
    }
}
