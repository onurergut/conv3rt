import Foundation
import AppKit
import ImageIO
import Conv3rtCore

/// One row in the file list: a source plus its inspection, plan and result.
@MainActor
final class ImportItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL

    @Published var info: ImageInfo?
    @Published var plan: ConversionPlan?
    @Published var state: ConversionJobState = .pending
    @Published var thumbnail: NSImage?
    @Published var loadError: String?
    @Published private(set) var isLoading = false
    private var hasLoaded = false
    private var inspectionTask: Task<(ImageInfo?, NSImage?, String?), Never>?
    /// Per-file output format override. nil targets the global format.
    @Published var formatOverrideID: String?

    var displayName: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url
    }

    /// True when the item can be converted under current settings.
    var isConvertible: Bool { plan?.status.isConvertible ?? false }

    var statusText: String {
        switch state {
        case .pending:
            if let loadError { return "Failed: \(loadError)" }
            if isLoading { return "Loading…" }
            return plan.map { $0.status == .blocked ? "Blocked" : ($0.status == .warning ? "Warning" : "Ready") } ?? "Waiting…"
        case .running(let p): return "Converting \(Int(p * 100))%"
        case .succeeded(let outs, _): return outs.count == 1 ? "Done" : "Done (\(outs.count) files)"
        case .failed(let m): return "Failed: \(m)"
        case .canceled: return "Canceled"
        }
    }

    var resultURLs: [URL] {
        if case .succeeded(let outs, _) = state { return outs }
        return []
    }

    /// Loads a small thumbnail and full inspection off the main thread.
    func load() async {
        guard !hasLoaded else { return }
        if inspectionTask == nil {
            isLoading = true
            let url = self.url
            inspectionTask = Task.detached(priority: .userInitiated) {
                let inspector = ImageInspector()
                var info: ImageInfo?
                var err: String?
                do { info = try inspector.inspect(url: url) }
                catch { err = error.localizedDescription }
                let thumb = Self.thumbnail(for: url)
                return (info, thumb, err)
            }
        }
        guard let inspectionTask else { return }
        let result = await inspectionTask.value
        guard !hasLoaded else { return }
        self.info = result.0
        self.thumbnail = result.1
        self.loadError = result.2
        hasLoaded = true
        isLoading = false
        self.inspectionTask = nil
    }

    nonisolated private static func thumbnail(for url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
