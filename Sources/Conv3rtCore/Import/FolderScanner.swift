import Foundation

/// Scans folders for image files with documented, safe behavior:
/// - Recurses into subfolders.
/// - Skips hidden files (leading dot) and package/bundle directories.
/// - Does not follow symlinks (avoids loops).
/// - De-duplicates by file identity (so aliases never add the same file twice).
/// - Keeps going when individual files are unreadable; returns them too so the
///   caller can show them as unsupported rather than silently dropping input.
public struct FolderScanner: Sendable {

    public struct Result: Sendable {
        public let imageFiles: [URL]
        public let skipped: [URL]
    }

    private let inspector: ImageInspector
    private static let imageExtensions = Set(FormatCatalog.all.flatMap(\.fileExtensions))

    public init(inspector: ImageInspector = ImageInspector()) {
        self.inspector = inspector
    }

    public func scan(urls: [URL], excluding existing: [URL] = []) -> Result {
        var seen = Set(existing.map { identity(for: $0) })
        var images: [URL] = []
        var skipped: [URL] = []

        for url in urls {
            if Task.isCancelled { break }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                recordSkipped(url, seen: &seen, skipped: &skipped)
                continue
            }
            if isDir.boolValue {
                enumerate(url, seen: &seen, images: &images, skipped: &skipped)
            } else {
                add(url, seen: &seen, images: &images, skipped: &skipped, allowUnknown: true)
            }
        }
        return Result(imageFiles: images, skipped: skipped)
    }

    private func enumerate(_ dir: URL, seen: inout Set<String>, images: inout [URL], skipped: inout [URL]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .nameKey]
        var inaccessible: [URL] = []
        guard FileManager.default.isReadableFile(atPath: dir.path) else {
            recordSkipped(dir, seen: &seen, skipped: &skipped)
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in inaccessible.append(url); return true }
        ) else {
            recordSkipped(dir, seen: &seen, skipped: &skipped)
            return
        }

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                recordSkipped(url, seen: &seen, skipped: &skipped)
                continue
            }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true { continue }
            add(url, seen: &seen, images: &images, skipped: &skipped, allowUnknown: false)
        }
        for url in inaccessible { recordSkipped(url, seen: &seen, skipped: &skipped) }
    }

    private func add(_ url: URL, seen: inout Set<String>, images: inout [URL],
                     skipped: inout [URL], allowUnknown: Bool) {
        guard seen.insert(identity(for: url)).inserted else { return }

        if inspector.isReadable(url: url) {
            images.append(url)
        } else if allowUnknown || Self.imageExtensions.contains(url.pathExtension.lowercased())
                    || !FileManager.default.isReadableFile(atPath: url.path) {
            skipped.append(url)
        }
    }

    private func recordSkipped(_ url: URL, seen: inout Set<String>, skipped: inout [URL]) {
        if seen.insert(identity(for: url)).inserted { skipped.append(url) }
    }

    private func identity(for url: URL) -> String {
        // File identity also handles aliases on case-insensitive volumes, while
        // preserving two genuinely different files on case-sensitive volumes.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
           let volume = attributes[.systemNumber] as? NSNumber,
           let file = attributes[.systemFileNumber] as? NSNumber {
            return "\(volume):\(file)"
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
