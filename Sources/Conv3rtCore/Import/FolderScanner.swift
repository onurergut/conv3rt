import Foundation

/// Scans folders for image files with documented, safe behavior:
/// - Recurses into subfolders.
/// - Skips hidden files (leading dot) and package/bundle directories.
/// - Does not follow symlinks (avoids loops).
/// - De-duplicates by resolved real path (so the same file is never added twice).
/// - Keeps going when individual files are unreadable; returns them too so the
///   caller can show them as unsupported rather than silently dropping input.
public struct FolderScanner: Sendable {

    public struct Result: Sendable {
        public let imageFiles: [URL]
        public let skipped: [URL]
    }

    private let inspector: ImageInspector

    public init(inspector: ImageInspector = ImageInspector()) {
        self.inspector = inspector
    }

    public func scan(urls: [URL]) -> Result {
        var seen = Set<String>()
        var images: [URL] = []
        var skipped: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
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
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true { continue }
            add(url, seen: &seen, images: &images, skipped: &skipped, allowUnknown: false)
        }
    }

    private func add(_ url: URL, seen: inout Set<String>, images: inout [URL],
                     skipped: inout [URL], allowUnknown: Bool) {
        let key = url.resolvingSymlinksInPath().standardizedFileURL.path
            .precomposedStringWithCanonicalMapping.lowercased()
        guard seen.insert(key).inserted else { return }

        if inspector.isReadable(url: url) {
            images.append(url)
        } else if allowUnknown {
            skipped.append(url)
        }
    }
}
