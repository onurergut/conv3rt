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

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conv3rt-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(in directory: URL) throws -> URL {
        let source = directory.appendingPathComponent("source.png")
        let image = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                          bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
                                                                       "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return source
    }
}
