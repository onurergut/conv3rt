import XCTest
@testable import Conv3rtCore

final class QueueSafetyTests: XCTestCase {
    private func job(width: Int = 8, height: Int = 8, frames: Int = 1,
                     source: URL = URL(fileURLWithPath: "/tmp/queue-safety.png"),
                     detectedUTI: String = "public.png",
                     settings: ConversionSettings = ConversionSettings(mode: .highestQuality),
                     blocked: Bool = true) -> ConversionJob {
        let info = ImageInfo(url: source, detectedUTI: detectedUTI, declaredUTI: detectedUTI,
                             fileSize: 0, pixelWidth: width, pixelHeight: height,
                             frameCount: frames, pageCount: 1, frameDurations: [], loopCount: nil,
                             canvasWidth: width, canvasHeight: height, bitsPerComponent: 8,
                             bitsPerPixel: 32, hasAlpha: true, colorModel: "RGB",
                             colorSpaceName: "sRGB", hasColorProfile: true, exifOrientation: nil,
                             hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false)
        let plan = ConversionPlan(source: info, targetUTI: "public.png", targetDisplayName: "PNG",
                                  codecId: "png", settings: settings,
                                  status: blocked ? .blocked : .ready, changes: [],
                                  expandsFramesOrPages: false, isStructural: false)
        return ConversionJob(source: source, info: info, plan: plan)
    }

    private func isTerminal(_ state: ConversionJobState) -> Bool {
        switch state {
        case .succeeded, .failed, .canceled: return true
        case .pending, .running: return false
        }
    }

    func testNonpositiveConcurrencyStillCompletesEveryJob() async {
        let output = TempDir()
        for cap in [0, -1, Int.min] {
            let runner = BatchRunner()
            let work = job()
            let finished = expectation(description: "Queue completes with concurrency \(cap)")
            let consumer = Task { () -> [QueueEvent] in
                var events: [QueueEvent] = []
                for await event in runner.run(jobs: [work], outputDirectory: output.url, maxConcurrency: cap) {
                    events.append(event)
                }
                finished.fulfill()
                return events
            }
            await fulfillment(of: [finished], timeout: 1)
            runner.cancel()
            consumer.cancel()
            let events = await consumer.value
            XCTAssertEqual(events.filter { isTerminal($0.state) }.count, 1)
        }
    }

    func testCancellationReportsTerminalEventForEveryUnscheduledJob() async {
        let output = TempDir()
        let runner = BatchRunner()
        let jobs = (0..<4).map { _ in job() }
        runner.cancel()
        var events: [QueueEvent] = []
        for await event in runner.run(jobs: jobs, outputDirectory: output.url) { events.append(event) }
        XCTAssertEqual(Set(events.map(\.jobID)), Set(jobs.map(\.id)))
        XCTAssertEqual(events.count, 4)
        XCTAssertTrue(events.allSatisfy { $0.state == .canceled })
        XCTAssertEqual(events.last?.completed, 4)
    }

    func testCancelingStreamConsumerSignalsTheWorkersToken() async {
        let output = TempDir()
        let runner = BatchRunner()
        let token = runner.currentToken
        let jobs = (0..<10_000).map { _ in job() }
        let consumer = Task {
            for await _ in runner.run(jobs: jobs, outputDirectory: output.url, maxConcurrency: 1) {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await consumer.value
        XCTAssertTrue(token.isCancelled, "Workers poll this token, so stream termination must cancel it")
    }

    func testNormalCompletionDoesNotCancelNextRun() async {
        let output = TempDir()
        let runner = BatchRunner()
        for _ in 0..<2 {
            var terminalCount = 0
            for await event in runner.run(jobs: [job()], outputDirectory: output.url) {
                if isTerminal(event.state) { terminalCount += 1 }
            }
            XCTAssertEqual(terminalCount, 1)
            XCTAssertFalse(runner.currentToken.isCancelled)
        }
    }

    func testConcurrentProgressCountsNeverDecrease() async {
        let output = TempDir()
        let runner = BatchRunner()
        let jobs = (0..<4_000).map { _ in job() }
        var completed = 0
        var regressions = 0
        for await event in runner.run(jobs: jobs, outputDirectory: output.url, maxConcurrency: 6) {
            if event.completed < completed { regressions += 1 }
            completed = max(completed, event.completed)
        }
        XCTAssertEqual(regressions, 0, "All events must observe the same serialized completion count")
        XCTAssertEqual(completed, jobs.count)
    }

    func testLargeWorkingSetsRunAloneEvenWithExplicitWorkerCount() async throws {
        let input = TempDir()
        let output = TempDir()
        let source = try Fixtures.write(Fixtures.manyColors(width: 512, height: 512), uti: "public.png",
                                        ext: "png", directory: input.url)
        // The source is small so the regression needs no large allocation. Its
        // inspection metadata models a large job at the scheduler boundary.
        let jobs = (0..<8).map { _ in job(width: 10_000, height: 10_000, source: source, blocked: false) }
        var active: Set<UUID> = []
        var peak = 0
        var succeeded = 0
        for await event in BatchRunner().run(jobs: jobs, outputDirectory: output.url, maxConcurrency: 6) {
            if case .running = event.state { active.insert(event.jobID); peak = max(peak, active.count) }
            if isTerminal(event.state) { active.remove(event.jobID) }
            if case .succeeded = event.state { succeeded += 1 }
        }
        XCTAssertEqual(peak, 1, "A worker override must not multiply a large estimated working set")
        XCTAssertEqual(succeeded, jobs.count)
    }

    func testConcurrencyUsesImageBytesInsteadOfOnlyHeavyFlags() throws {
        guard ProcessInfo.processInfo.activeProcessorCount > 2 else { throw XCTSkip("Needs multiple workers") }
        let small = job(width: 100, height: 100, frames: 40)
        let large = job(width: 2_000, height: 2_000, frames: 40)
        XCTAssertGreaterThan(BatchRunner.concurrency(for: [small]), 1)
        XCTAssertEqual(BatchRunner.concurrency(for: [large]), 1)
    }

    func testExtremeDimensionsCannotOverflowConcurrencyEstimate() {
        XCTAssertEqual(BatchRunner.concurrency(for: [job(width: Int.max, height: Int.max)]), 1)
    }

    func testHigherPDFResolutionReducesConcurrentWorkingSets() throws {
        guard ProcessInfo.processInfo.activeProcessorCount > 2 else { throw XCTSkip("Needs multiple workers") }
        let normal = job(width: 4_000, height: 4_000, detectedUTI: "com.adobe.pdf",
                         settings: ConversionSettings(mode: .highestQuality, pdfDPI: 144))
        let high = job(width: 4_000, height: 4_000, detectedUTI: "com.adobe.pdf",
                       settings: ConversionSettings(mode: .highestQuality, pdfDPI: 576))
        XCTAssertGreaterThan(BatchRunner.concurrency(for: [normal]), 1)
        XCTAssertEqual(BatchRunner.concurrency(for: [high]), 1)
    }

    func testHigherSVGScaleReducesConcurrentWorkingSets() throws {
        guard ProcessInfo.processInfo.activeProcessorCount > 2 else { throw XCTSkip("Needs multiple workers") }
        let normal = job(width: 4_000, height: 4_000, detectedUTI: "public.svg-image",
                         settings: ConversionSettings(mode: .highestQuality, svgScale: 2))
        let high = job(width: 4_000, height: 4_000, detectedUTI: "public.svg-image",
                       settings: ConversionSettings(mode: .highestQuality, svgScale: 8))
        XCTAssertGreaterThan(BatchRunner.concurrency(for: [normal]), 1)
        XCTAssertEqual(BatchRunner.concurrency(for: [high]), 1)
    }
}
