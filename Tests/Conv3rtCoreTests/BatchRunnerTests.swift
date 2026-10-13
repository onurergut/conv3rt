import XCTest
@testable import Conv3rtCore

final class BatchRunnerTests: XCTestCase {

    func testPNGRunDeliversProgressAndFinishes() async throws {
        let directory = TempDir()
        let source = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                        directory: directory.url)
        let info = try ImageInspector().inspect(url: source)
        let target = try XCTUnwrap(CapabilityRegistry.shared.capability(id: "png"))
        let plan = ConversionPlanner().plan(source: info, target: target, settings: ConversionSettings())
        let job = ConversionJob(source: source, info: info, plan: plan)
        let runner = BatchRunner()
        let finished = expectation(description: "The queue completes the PNG conversion")
        let consumer = Task { () -> [QueueEvent] in
            var events: [QueueEvent] = []
            for await event in runner.run(jobs: [job], outputDirectory: directory.url) {
                events.append(event)
            }
            finished.fulfill()
            return events
        }
        await fulfillment(of: [finished], timeout: 2)
        consumer.cancel()
        let events = await consumer.value
        XCTAssertTrue(events.allSatisfy { $0.jobID == job.id })
        XCTAssertTrue(events.contains { if case .running(let p) = $0.state { return p > 0 }; return false })
        let last = try XCTUnwrap(events.last)
        XCTAssertEqual(last.fraction, 1)
        guard case .succeeded(let outputs, _) = last.state else {
            return XCTFail("Expected a successful terminal event, got \(last.state)")
        }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[0].path))
    }
}
