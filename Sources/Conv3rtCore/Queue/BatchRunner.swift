import Foundation

/// Runs conversion jobs with bounded concurrency and reports progress, cancel
/// and retry as an `AsyncStream` of events.
///
/// Concurrency is bounded by CPU count and estimated image working sets.
/// A job larger than the concurrency budget runs alone; the planner controls
/// which individual jobs are allowed. Codec work runs in worker tasks.
public final class BatchRunner: @unchecked Sendable {

    private let engine: ConversionEngine
    private let verifier: OutputVerifier
    private let namer: OutputNamer

    public init(engine: ConversionEngine = ConversionEngine(),
                verifier: OutputVerifier = OutputVerifier(),
                namer: OutputNamer = OutputNamer()) {
        self.engine = engine
        self.verifier = verifier
        self.namer = namer
    }

    /// Suggested worker count for this batch.
    public static func concurrency(for jobs: [ConversionJob]) -> Int {
        let cpus = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let base = max(1, min(cpus - 1, 6))
        let largest = jobs.map { estimatedWorkingBytes(of: $0) }.max() ?? 1
        let memoryWorkers = memoryBudget / min(largest, memoryBudget)
        return max(1, min(base, Int(memoryWorkers)))
    }

    /// Reserve up to a quarter of physical RAM, capped at 1 GiB, for concurrent
    /// working sets. This does not reject or resize an individual conversion.
    private static var memoryBudget: UInt64 {
        max(1, min(ProcessInfo.processInfo.physicalMemory / 4, 1_024 * 1_024 * 1_024))
    }

    private static func estimatedWorkingBytes(of job: ConversionJob) -> UInt64 {
        let info = job.info
        // Inspection renders documents at the factory defaults. Account for a
        // later resolution increase before allowing concurrent rasterization.
        let renderScale: Double
        switch info.detectedUTI ?? info.declaredUTI {
        case "com.adobe.pdf": renderScale = job.plan.settings.pdfDPI / 144
        case "public.svg-image": renderScale = job.plan.settings.svgScale / 2
        default: renderScale = 1
        }
        let width = scaled(UInt64(max(info.pixelWidth, info.canvasWidth, 1)), by: renderScale)
        let height = scaled(UInt64(max(info.pixelHeight, info.canvasHeight, 1)), by: renderScale)
        let depth = UInt64(max(info.bitsPerComponent, 8))
        let pixelBits = UInt64(max(info.bitsPerPixel, 32))
        let componentBytes = depth / 8 + (depth % 8 == 0 ? 0 : 1)
        let pixelBytes = max(product(componentBytes, 4), pixelBits / 8 + (pixelBits % 8 == 0 ? 0 : 1))
        // Split exports and first-frame exports only retain one frame at a time.
        let frames = job.plan.expandsFramesOrPages || job.plan.settings.framePolicy == .firstOnly
            ? 1 : UInt64(max(info.frameCount, info.pageCount, 1))
        // Allow for decoded pixels, preparation, encoding and verification.
        return product(product(product(product(width, height), pixelBytes), frames), 4)
    }

    private static func product(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }

    private static func scaled(_ dimension: UInt64, by factor: Double) -> UInt64 {
        guard factor.isFinite, factor > 0 else { return UInt64.max }
        guard factor > 1 else { return dimension }
        let estimate = (Double(dimension) * factor).rounded(.up)
        guard estimate < Double(UInt64.max) else { return UInt64.max }
        return UInt64(estimate)
    }

    public func run(jobs: [ConversionJob], outputDirectory: URL,
                    registry: CapabilityRegistry = .shared,
                    maxConcurrency: Int? = nil) -> AsyncStream<QueueEvent> {
        let token = currentToken
        let concurrency = max(1, min(maxConcurrency ?? Self.concurrency(for: jobs), 6))
        let memoryBudget = Self.memoryBudget
        let engine = self.engine
        let verifier = self.verifier
        let namer = self.namer
        let total = jobs.count

        return AsyncStream { continuation in
            let events = EventEmitter(continuation: continuation, total: total)
            let task = Task {
                await withTaskGroup(of: UInt64.self) { group in
                    var index = 0
                    var running = 0
                    var runningBytes: UInt64 = 0
                    while index < jobs.count {
                        if token.isCancelled || Task.isCancelled {
                            for job in jobs[index...] { events.yield(job.id, .canceled, completing: true) }
                            break
                        }
                        let cost = min(Self.estimatedWorkingBytes(of: jobs[index]), memoryBudget)
                        if running < concurrency && cost <= memoryBudget - runningBytes {
                            let job = jobs[index]; index += 1; running += 1
                            runningBytes += cost
                            let id = job.id
                            events.yield(id, .pending)
                            group.addTask {
                                if token.isCancelled || Task.isCancelled {
                                    events.yield(id, .canceled, completing: true)
                                    return cost
                                }
                                events.yield(id, .running(0))
                                let result: ConversionJobState
                                guard let target = registry.capability(uti: job.plan.targetUTI) else {
                                    result = .failed(message: "Target format is no longer available.")
                                    events.yield(id, result, completing: true)
                                    return cost
                                }
                                var jobDir = outputDirectory
                                if let sub = job.outputSubdirectory, !sub.isEmpty {
                                    jobDir = outputDirectory.appendingPathComponent(sub, isDirectory: true)
                                    try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)
                                }
                                do {
                                    let r = try engine.convert(
                                        plan: job.plan, outputDirectory: jobDir,
                                        namer: namer, verifier: verifier, target: target,
                                        isCancelled: { token.isCancelled || Task.isCancelled },
                                        progress: { p in
                                            events.yield(id, .running(p))
                                        })
                                    result = .succeeded(outputs: r.outputs, notes: r.notes)
                                } catch let error as ConversionError {
                                    if case .canceled = error { result = .canceled }
                                    else { result = .failed(message: error.localizedDescription) }
                                } catch {
                                    result = .failed(message: error.localizedDescription)
                                }
                                events.yield(id, result, completing: true)
                                return cost
                            }
                        } else {
                            if let finishedCost = await group.next() {
                                running -= 1
                                runningBytes -= finishedCost
                            }
                        }
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason {
                    token.cancel()
                    task.cancel()
                }
            }
        }
    }

    // Cancellation token shared across a run.
    private let tokenLock = NSLock()
    private var _token = CancelToken()
    /// The token used by the next `run`. Call `cancel()` to stop.
    public var currentToken: CancelToken {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return _token
    }
    public func resetCancellation() {
        tokenLock.lock(); defer { tokenLock.unlock() }
        _token = CancelToken()
    }
    public func cancel() {
        tokenLock.lock(); defer { tokenLock.unlock() }
        _token.cancel()
    }
}

/// Serializes count updates and all event emission so concurrent workers cannot
/// publish an older completed count after a newer one.
private final class EventEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let continuation: AsyncStream<QueueEvent>.Continuation
    private let total: Int

    init(continuation: AsyncStream<QueueEvent>.Continuation, total: Int) {
        self.continuation = continuation
        self.total = total
    }

    func yield(_ id: UUID, _ state: ConversionJobState, completing: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if completing { count += 1 }
        continuation.yield(QueueEvent(jobID: id, state: state, completed: count, total: total))
    }
}
