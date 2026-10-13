import Foundation
import AppKit
import SwiftUI
import Combine
import Conv3rtCore

/// The app's single source of truth, bound to the views. Runs on the main actor;
/// all heavy work is offloaded.
@MainActor
final class AppModel: ObservableObject {

    let registry = CapabilityRegistry.shared
    private let planner = ConversionPlanner()
    private let scanner = FolderScanner()
    private let defaults: UserDefaults
    private let presetStore: PresetStore
    private var runner = BatchRunner()
    private var itemChanges: AnyCancellable?

    @Published var items: [ImportItem] = [] {
        didSet {
            itemChanges = Publishers.MergeMany(items.map(\.objectWillChange)).sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var statusLine: String = "Add images to begin."
    @Published var lastError: String?

    // Persisted settings.
    @Published var selectedFormatID: String { didSet { persist(); recomputePlans() } }
    @Published var mode: ConversionMode { didSet { persist(); recomputePlans() } }
    @Published var metadataPolicy: MetadataPolicy { didSet { persist(); recomputePlans() } }
    @Published var framePolicy: FramePolicy { didSet { persist(); recomputePlans() } }
    @Published var alphaBackground: AlphaBackground { didSet { persist(); recomputePlans() } }
    @Published var lossyQuality: Double { didSet { persist() } }
    @Published var pdfDPI: Double { didSet { persist(); recomputePlans() } }
    @Published var svgScale: Double { didSet { persist(); recomputePlans() } }
    @Published var keepFolderStructure: Bool { didSet { persist() } }
    @Published var outputDirectory: URL? { didSet { persistOutputFolder() } }
    @Published private(set) var recentOutputFolders: [URL] = []
    @Published private(set) var presets: [ConversionPreset] = []

    var selectedFormat: FormatCapability? {
        registry.capability(id: selectedFormatID) ?? registry.writableFormats().first
    }
    var writableFormats: [FormatCapability] { registry.writableFormats() }

    // MARK: - Init / persistence

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.presetStore = PresetStore(defaults: defaults)
        let d = defaults
        self.selectedFormatID = d.string(forKey: Keys.format) ?? "png"
        self.mode = ConversionMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .lossless
        self.metadataPolicy = MetadataPolicy(rawValue: d.string(forKey: Keys.metadata) ?? "") ?? .keep
        self.framePolicy = FramePolicy(rawValue: d.string(forKey: Keys.framePolicy) ?? "") ?? .undecided
        self.alphaBackground = AlphaBackground.fromStorage(d.string(forKey: Keys.alphaBG))
        self.lossyQuality = d.object(forKey: Keys.quality) as? Double ?? 0.9
        self.pdfDPI = d.object(forKey: Keys.pdfDPI) as? Double ?? 144
        self.svgScale = d.object(forKey: Keys.svgScale) as? Double ?? 2.0
        self.keepFolderStructure = d.bool(forKey: Keys.keepFolders)
        if let paths = d.stringArray(forKey: Keys.recentOutputs) {
            self.recentOutputFolders = paths.map { URL(fileURLWithPath: $0) }
        }
        if let path = d.string(forKey: Keys.output), FileManager.default.fileExists(atPath: path) {
            self.outputDirectory = URL(fileURLWithPath: path)
        }
        self.presets = presetStore.load()
    }

    private enum Keys {
        static let format = "conv3rt.format"
        static let mode = "conv3rt.mode"
        static let metadata = "conv3rt.metadata"
        static let framePolicy = "conv3rt.framePolicy"
        static let alphaBG = "conv3rt.alphaBG"
        static let quality = "conv3rt.quality"
        static let pdfDPI = "conv3rt.pdfDPI"
        static let svgScale = "conv3rt.svgScale"
        static let keepFolders = "conv3rt.keepFolders"
        static let output = "conv3rt.output"
        static let recentOutputs = "conv3rt.recentOutputs"
    }

    private func persist() {
        defaults.set(selectedFormatID, forKey: Keys.format)
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(metadataPolicy.rawValue, forKey: Keys.metadata)
        defaults.set(framePolicy.rawValue, forKey: Keys.framePolicy)
        defaults.set(alphaBackground.storageString, forKey: Keys.alphaBG)
        defaults.set(lossyQuality, forKey: Keys.quality)
        defaults.set(pdfDPI, forKey: Keys.pdfDPI)
        defaults.set(svgScale, forKey: Keys.svgScale)
        defaults.set(keepFolderStructure, forKey: Keys.keepFolders)
    }

    private func persistOutputFolder() {
        defaults.set(outputDirectory?.path, forKey: Keys.output)
        guard let dir = outputDirectory else { return }
        var recents = recentOutputFolders.filter { $0.path != dir.path }
        recents.insert(dir, at: 0)
        recentOutputFolders = Array(recents.prefix(5))
        defaults.set(recentOutputFolders.map(\.path), forKey: Keys.recentOutputs)
    }

    // MARK: - Presets

    /// Snapshots the current settings under `name`. Replaces any preset with the
    /// same name (case-insensitive).
    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = ConversionPreset(
            name: trimmed,
            formatID: selectedFormatID,
            mode: mode,
            metadataPolicy: metadataPolicy,
            framePolicy: framePolicy,
            alphaBackground: alphaBackground,
            lossyQuality: lossyQuality,
            pdfDPI: pdfDPI,
            svgScale: svgScale,
            keepFolderStructure: keepFolderStructure
        )
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        presetStore.save(presets)
        statusLine = "Saved preset “\(trimmed)”."
    }

    func applyPreset(_ preset: ConversionPreset) {
        selectedFormatID = preset.formatID
        mode = preset.mode
        metadataPolicy = preset.metadataPolicy
        framePolicy = preset.framePolicy
        alphaBackground = preset.alphaBackground
        lossyQuality = preset.lossyQuality
        pdfDPI = preset.pdfDPI
        svgScale = preset.svgScale
        keepFolderStructure = preset.keepFolderStructure
        statusLine = "Applied preset “\(preset.name)”."
    }

    func deletePreset(_ preset: ConversionPreset) {
        presets.removeAll { $0.id == preset.id }
        presetStore.save(presets)
    }

    // MARK: - Import

    func addFiles(_ urls: [URL], load: Bool = true) {
        let result = scanner.scan(urls: urls)
        var additions: [ImportItem] = []
        for url in result.imageFiles where !items.contains(where: { $0.url == url }) {
            additions.append(ImportItem(url: url))
        }
        if !additions.isEmpty { items.append(contentsOf: additions) }
        let added = additions.count
        if !result.skipped.isEmpty {
            statusLine = "Added \(added). Skipped \(result.skipped.count) unsupported file(s)."
        } else {
            statusLine = added > 0 ? "Added \(added) file(s)." : "No new images found."
        }
        if load { Task { await loadAll() } }
    }

    /// Entry point for Finder Quick Actions / Open With: import, wait for
    /// inspection, then convert with the current settings.
    func handleService(_ urls: [URL]) {
        if outputDirectory == nil, let first = urls.first {
            // No folder chosen yet: default to the source's own folder so a
            // Quick Action produces a result without any dialog.
            outputDirectory = first.deletingLastPathComponent()
        }
        Task { await importAndConvert(urls) }
    }

    private func importAndConvert(_ urls: [URL]) async {
        addFiles(urls, load: false)
        await loadAll()
        guard outputDirectory != nil else {
            lastError = "Choose an output folder first."
            return
        }
        startConversion()
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
        let settings = currentSettings
        for item in items {
            guard let info = item.info else { continue }
            let target = item.formatOverrideID.flatMap { registry.capability(id: $0) } ?? selectedFormat
            guard let target else { continue }
            item.plan = planner.plan(source: info, target: target, settings: settings)
        }
    }

    /// Sets or clears a per-file output-format override and replans that item.
    func setFormatOverride(_ id: String?, for item: ImportItem) {
        guard item.formatOverrideID != id else { return }
        item.formatOverrideID = id
        recomputePlans()
    }

    var currentSettings: ConversionSettings {
        ConversionSettings(mode: mode, metadataPolicy: metadataPolicy,
                           framePolicy: framePolicy, alphaBackground: alphaBackground,
                           pdfDPI: pdfDPI, svgScale: svgScale,
                           keepFolderStructure: keepFolderStructure)
    }

    func openOutputFolder() {
        guard let dir = outputDirectory else { return }
        NSWorkspace.shared.open(dir)
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
            let sub = keepFolderStructure ? item.url.deletingLastPathComponent().lastPathComponent : nil
            return ConversionJob(source: item.url, info: info, plan: plan, outputSubdirectory: sub)
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
            NSSound(named: "Glass")?.play()
            NSApp.activate(ignoringOtherApps: true)
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

    func useRecentOutputFolder(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            recentOutputFolders.removeAll { $0.path == url.path }
            defaults.set(recentOutputFolders.map(\.path), forKey: Keys.recentOutputs)
            lastError = "That folder is no longer available."
            return
        }
        outputDirectory = url
    }
}
