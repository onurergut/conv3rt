import Foundation

/// Chooses collision-free output file names.
///
/// Never overwrites existing files (default policy). Case-insensitive and
/// Unicode-aware, matching typical macOS (APFS/HFS+) semantics. Thread-safe and
/// aware of names reserved during the same run, so concurrent jobs cannot pick
/// the same target.
public final class OutputNamer: @unchecked Sendable {

    private let lock = NSLock()
    private var reserved: Set<String> = []

    public init() {}

    /// Returns a unique file URL in `directory` for `baseName` with `fileExtension`,
    /// applying `name-1.ext`, `name-2.ext`, … on conflict.
    public func uniqueURL(in directory: URL, baseName: String, fileExtension ext: String) -> URL {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let safeExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext

        var candidate = directory.appendingPathComponent(filename(baseName, safeExt))
        var counter = 1
        while exists(candidate, fm: fm) || reserved.contains(key(candidate)) {
            candidate = directory.appendingPathComponent(filename("\(baseName)-\(counter)", safeExt))
            counter += 1
        }
        reserved.insert(key(candidate))
        return candidate
    }

    /// Releases a previously reserved name (e.g. when a job fails before writing).
    public func release(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        reserved.remove(key(url))
    }

    private func filename(_ base: String, _ ext: String) -> String {
        ext.isEmpty ? base : "\(base).\(ext)"
    }

    private func key(_ url: URL) -> String {
        url.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func exists(_ url: URL, fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.path)
    }
}
