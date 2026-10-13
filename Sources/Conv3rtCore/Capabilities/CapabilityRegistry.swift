import Foundation

/// The single source of truth for "what can this machine do right now".
///
/// It merges the runtime probe (which formats macOS can actually read/write on
/// this machine) with the static `FormatCatalog` (what each format can
/// represent). The UI and the conversion planner both read from here, so they
/// can never disagree about support.
public final class CapabilityRegistry: @unchecked Sendable {

    public static let shared = CapabilityRegistry()

    private let probe: RuntimeTypeProbe
    private let lock = NSLock()
    private var cached: [FormatCapability]?

    public init(probe: RuntimeTypeProbe = RuntimeTypeProbe()) {
        self.probe = probe
    }

    /// All capabilities, with read/write flags set from the live probe.
    public func capabilities() -> [FormatCapability] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let built = Self.build(probe: probe)
        cached = built
        return built
    }

    public func capability(uti: String) -> FormatCapability? {
        capabilities().first { $0.uti == uti }
    }

    public func capability(id: String) -> FormatCapability? {
        capabilities().first { $0.id == id }
    }

    /// Formats usable as conversion targets, sorted by display name.
    public func writableFormats() -> [FormatCapability] {
        capabilities().filter { $0.canWrite }.sorted { $0.displayName < $1.displayName }
    }

    /// Formats usable as conversion sources, sorted by display name.
    public func readableFormats() -> [FormatCapability] {
        capabilities().filter { $0.canRead }.sorted { $0.displayName < $1.displayName }
    }

    public func snapshot() -> RuntimeTypeProbe.Snapshot { probe.snapshot() }

    // MARK: - Build

    static func build(probe: RuntimeTypeProbe) -> [FormatCapability] {
        let snap = probe.snapshot()
        var result: [FormatCapability] = []
        var seenUTIs = Set<String>()

        // 1. Catalog entries, with live read/write flags.
        for var c in FormatCatalog.all {
            switch c.provider {
            case .imageIO:
                // Read is real when the exact UTI is readable OR when any
                // readable UTI conforms to it (RAW families share a base UTI
                // such as public.raw-image that is never listed directly).
                c.canRead = snap.readableUTIs.contains(c.uti)
                    || snap.readableUTIs.contains { UTTypeBridge.conformance($0, toIdentifier: c.uti) }
                c.canWrite = snap.writableUTIs.contains(c.uti)
            case .pdfKit:
                // PDF is decoded through PDFKit, not Image I/O source types.
                c.canRead = true
                c.canWrite = snap.writableUTIs.contains(c.uti)
            case .bundled, .builtin:
                // Provided by conv3rt itself (e.g. SVG rasterization).
                c.canRead = true
            }
            // WebP and JPEG XL are read by Image I/O but written by a bundled
            // codec; their write capability follows the codec's availability.
            if c.id == "webp" {
                c.canWrite = WebPEncoder.isAvailable
            }
            if c.id == "jxl" {
                c.canWrite = JXLEncoder.isAvailable
            }
            result.append(c)
            seenUTIs.insert(c.uti)
        }

        // 2. Any runtime type we know nothing about: surface it honestly as
        //    "detected, capabilities unverified" instead of hiding it.
        for uti in snap.readableUTIs.union(snap.writableUTIs) where !seenUTIs.contains(uti) {
            let ext = FormatCatalogHelper.primaryExtension(for: uti)
            var c = FormatCapability(
                id: "runtime.\(uti)",
                uti: uti,
                displayName: FormatCatalogHelper.displayName(for: uti),
                fileExtensions: ext.map { [$0] } ?? []
            )
            c.canRead = snap.readableUTIs.contains(uti)
            c.canWrite = snap.writableUTIs.contains(uti)
            c.evidence = .documented
            c.limitations = ["Detected from the system but not yet characterized by conv3rt."]
            result.append(c)
        }

        return result
    }
}

enum FormatCatalogHelper {
    static func primaryExtension(for uti: String) -> String? {
        UTTypeBridge.preferredFilenameExtension(uti)
    }

    static func displayName(for uti: String) -> String {
        if let d = UTTypeBridge.localizedDescription(uti) { return d }
        return uti
    }
}
