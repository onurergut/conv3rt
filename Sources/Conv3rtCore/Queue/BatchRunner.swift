import Foundation

/// Runs conversion jobs with bounded concurrency and reports progress, cancel
/// and retry as an `AsyncStream` of events.
///
/// Concurrency is bounded by CPU count *and* per-job weight (a 16-bit 8-frame
/// image weighs more than a small 8-bit one), so a batch does not exhaust
/// memory. Heavy codec work never runs on the caller's thread.
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
        // If any job is heavy, scale down to avoid multiplying memory.
        let heavy = jobs.contains { weight(of: $0) >= 2 }
        return heavy ? max(1, base / 2) : base
    }

    /// Per-job cost weight (1 = light, 2 = heavy).
    static func weight(of job: ConversionJob) -> Int {
        let pixels = max(job.info.pixelWidth * job.info.pixelHeight, 1)
        let frames = max(job.info.frameCount, job.info.pageCount)
        let depth = job.info.bitsPerComponent
        var w = 1
        if pixels > 16_000_000 { w += 1 }          // > ~16 MP
        if frames > 1 { w += 1 }
        if depth >= 16 { w += 1 }
        return w
    }

    public func run(jobs: [ConversionJob], outputDirectory: URL,
                    registry: CapabilityRegistry = .shared,
                    maxConcurrency: Int? = nil) -> AsyncStream<QueueEvent> {
        let token = currentToken
        let concurrency = maxConcurrency ?? Self.concurrency(for: jobs)
        let engine = self.engine
        let verifier = self.verifier
        let namer = self.namer
        let total = jobs.count

        return AsyncStream { continuation in
            let counter = Counter()
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    var index = 0
                    var running = 0
                    while index < jobs.count {
                        if token.isCancelled { break }
                        if running < concurrency {
                            let job = jobs[index]; index += 1; running += 1
                            let id = job.id
                            continuation.yield(QueueEvent(jobID: id, state: .pending, completed: counter.value, total: total))
                            group.addTask {
                                continuation.yield(QueueEvent(jobID: id, state: .running(0), completed: counter.value, total: total))
                                let result: ConversionJobState
                                guard let target = registry.capability(uti: job.plan.targetUTI) else {
                                    result = .failed(message: "Target format is no longer available.")
                                    continuation.yield(QueueEvent(jobID: id, state: result, completed: counter.increment(), total: total))
                                    return
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
                                        isCancelled: { token.isCancelled },
                                        progress: { p in
                                            continuation.yield(QueueEvent(jobID: id, state: .running(p),
                                                                          completed: counter.value, total: total))
                                        })
                                    result = .succeeded(outputs: r.outputs, notes: r.notes)
                                } catch let error as ConversionError {
                                    if case .canceled = error { result = .canceled }
                                    else { result = .failed(message: error.localizedDescription) }
                                } catch {
                                    result = .failed(message: error.localizedDescription)
                                }
                                continuation.yield(QueueEvent(jobID: id, state: result, completed: counter.increment(), total: total))
                            }
                        } else {
                            await group.next()
                            running -= 1
                        }
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Cancellation token shared across a run.
    private var _token = CancelToken()
    /// The token used by the next `run`. Call `cancel()` to stop.
    public var currentToken: CancelToken { _token }
    public func resetCancellation() { _token = CancelToken() }
    public func cancel() { _token.cancel() }
}

/// Small lock-based counter for completed jobs.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
