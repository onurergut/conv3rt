import Foundation

/// A single unit of work: one source with its plan.
public struct ConversionJob: Identifiable, Sendable {
    public let id: UUID
    public let source: URL
    public let info: ImageInfo
    public let plan: ConversionPlan
    /// Optional sub-path under the output folder, used to mirror the source's
    /// folder structure. nil means write directly into the output folder.
    public let outputSubdirectory: String?

    public init(id: UUID = UUID(), source: URL, info: ImageInfo, plan: ConversionPlan,
                outputSubdirectory: String? = nil) {
        self.id = id
        self.source = source
        self.info = info
        self.plan = plan
        self.outputSubdirectory = outputSubdirectory
    }
}

/// Lifecycle of a job in the queue.
public enum ConversionJobState: Sendable, Equatable {
    case pending
    case running(Double)               // 0…1
    case succeeded(outputs: [URL], notes: [String])
    case failed(message: String)
    case canceled
}

/// An event emitted as jobs progress.
public struct QueueEvent: Sendable {
    public let jobID: UUID
    public let state: ConversionJobState
    public let completed: Int
    public let total: Int

    public var fraction: Double {
        total == 0 ? 1 : Double(completed) / Double(total)
    }
}

/// Thread-safe cancellation token shared with workers.
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    public func reset() { lock.lock(); flag = false; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
