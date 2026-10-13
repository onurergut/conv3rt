import Foundation
import AppKit
import SwiftUI
import Conv3rtCore

/// The app's single source of truth, bound to the views. Runs on the main actor;
/// all heavy work is offloaded.
@MainActor
final class AppModel: ObservableObject {

    let registry = CapabilityRegistry.shared
    private let planner = ConversionPlanner()
    private let scanner = FolderScanner()
    private let defaults = UserDefaults.standard
    private var runner = BatchRunner()

    @Published var items: [ImportItem] = []
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusLine: String = "Add images to begin."
    @Published var lastError: String?

    // Persisted settings.
    @Published var selectedFormatID: String { didSet { persist() } }
    @Published var mode: ConversionMode { didSet { persist(); recomputePlans() } }
    @Published var metadataPolicy: MetadataPolicy { didSet { persist(); recomputePlans() } }
    @Published var framePolicy: FramePolicy { didSet { persist(); recomputePlans() } }
    @Published var alphaBackground: AlphaBackground { didSet { persist(); recomputePlans() } }
    @Published var lossyQuality: Double { didSet { persist() } }
    @Published var outputDirectory: URL? { didSet { persistOutputFolder() } }

    var selectedFormat: FormatCapability? {
        registry.capability(id: selectedFormatID) ?? registry.writableFormats().first
    }
    var writableFormats: [FormatCapability] { registry.writableFormats() }

    // MARK: - Init / persistence

    init() {
        let d = UserDefaults.standard
        self.selectedFormatID = d.string(forKey: Keys.format) ?? "png"
        self.mode = ConversionMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .lossless
        self.metadataPolicy = MetadataPolicy(rawValue: d.string(forKey: Keys.metadata) ?? "") ?? .keep
        self.framePolicy = FramePolicy(rawValue: d.string(forKey: Keys.framePolicy) ?? "") ?? .undecided
        let bg = d.string(forKey: Keys.alphaBG) ?? "white"
        self.alphaBackground = (bg == "black") ? .black : .white
        self.lossyQuality = d.object(forKey: Keys.quality) as? Double ?? 0.9
        if let path = d.string(forKey: Keys.output), FileManager.default.fileExists(atPath: path) {
            self.outputDirectory = URL(fileURLWithPath: path)
        }
        if let saved = d.string(forKey: Keys.lastOutput) { /* retained for future use */ _ = saved }
    }

    private enum Keys {
        static let format = "conv3rt.format"
        static let mode = "conv3rt.mode"
        static let metadata = "conv3rt.metadata"
        static let framePolicy = "conv3rt.framePolicy"
        static let alphaBG = "conv3rt.alphaBG"
        static let quality = "conv3rt.quality"
        static let output = "conv3rt.output"
        static let lastOutput = "conv3rt.lastOutput"
    }

    private func persist() {
        defaults.set(selectedFormatID, forKey: Keys.format)
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(metadataPolicy.rawValue, forKey: Keys.metadata)
        defaults.set(framePolicy.rawValue, forKey: Keys.framePolicy)
        switch alphaBackground {
        case .black: defaults.set("black", forKey: Keys.alphaBG)
        case .white: defaults.set("white", forKey: Keys.alphaBG)
        case .custom: defaults.set("white", forKey: Keys.alphaBG)
        }
        defaults.set(lossyQuality, forKey: Keys.quality)
    }

    private func persistOutputFolder() {
        defaults.set(outputDirectory?.path, forKey: Keys.output)
    }

    // MARK: - Import

    func addFiles(_ urls: [URL]) {
        let result = scanner.scan(urls: urls)
        var added = 0
        for url in result.imageFiles where !items.contains(where: { $0.url == url }) {
            let item = ImportItem(url: url)
            items.append(item)
            added += 1
        }
        if !result.skipped.isEmpty {
            statusLine = "Added \(added). Skipped \(result.skipped.count) unsupported file(s)."
        } else {
            statusLine = added > 0 ? "Added \(added) file(s)." : "No new images found."
        }
        Task { await loadAll() }
    }

    func addFolder(_ url: URL) { addFiles([url]) }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        // Prefer a real image representation over file URLs.
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if let type = imageTypes.first(where: { pb.data(forType: $0) != nil }),
           let data = pb.data(forType: type) {
            let dir = FileManager.default.temporaryDirectory
            let ext = type == .png ? "png" : "tiff"
            let url = dir.appendingPathComponent("conv3rt-clipboard-\(UUID().uuidString).\(ext)")
            do {
                try data.write(to: url)
                addFiles([url])
                statusLine = "Pasted image from clipboard."
            } catch { lastError = "Could not read the clipboard image." }
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            addFiles(urls)
            return
        }
        lastError = "The clipboard does not contain an image."
    }

    func remove(_ item: ImportItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items.removeAll()
        statusLine = "Add images to begin."
        progress = 0
    }

    private func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask { await item.load() }
            }
        }
        recomputePlans()
    }

    // MARK: - Planning

    func recomputePlans() {
        guard let target = selectedFormat else { return }
        let settings = currentSettings
        for item in items {
            guard let info = item.info else { continue }
            item.plan = planner.plan(source: info, target: target, settings: settings)
        }
    }

    var currentSettings: ConversionSettings {
        ConversionSettings(mode: mode, metadataPolicy: metadataPolicy,
                           framePolicy: framePolicy, alphaBackground: alphaBackground)
    }

    // MARK: - Conversion

    var convertibleCount: Int { items.filter { $0.isConvertible }.count }
    var blockedCount: Int { items.filter { $0.plan?.status == .blocked }.count }

    func startConversion() {
        guard !isRunning else { return }
        guard let output = outputDirectory else {
            lastError = "Choose an output folder first."
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: output.path, isDirectory: &isDir), isDir.boolValue else {
            lastError = "The output folder is unavailable. Choose another folder."
            return
        }
        let jobs: [ConversionJob] = items.compactMap { item in
            guard let info = item.info, let plan = item.plan, plan.status.isConvertible else { return nil }
            return ConversionJob(source: item.url, info: info, plan: plan)
        }
        guard !jobs.isEmpty else {
            lastError = "No convertible files. Check the format and quality settings."
            return
        }

        runner = BatchRunner(engine: ConversionEngine(quality: lossyQuality))
        isRunning = true
        progress = 0
        statusLine = "Converting \(jobs.count) file(s)…"
        for item in items { item.state = .pending }

        let jobToSource = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.source) })
        let itemBySource = Dictionary(uniqueKeysWithValues: items.map { ($0.url, $0) })

        Task {
            for await event in runner.run(jobs: jobs, outputDirectory: output, registry: registry) {
                progress = event.fraction
                if let url = jobToSource[event.jobID] {
                    itemBySource[url]?.state = event.state
                }
            }
            isRunning = false
            let done = items.filter { if case .succeeded = $0.state { return true }; return false }.count
            let failed = items.filter { if case .failed = $0.state { return true }; return false }.count
            progress = 1
            statusLine = "Finished: \(done) succeeded, \(failed) failed."
        }
    }

    func cancel() {
        runner.cancel()
        statusLine = "Canceling…"
    }

    func retryFailed() {
        for item in items {
            if case .failed = item.state { item.state = .pending }
        }
        startConversion()
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Output folder picker

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the output folder for converted images."
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }
}
