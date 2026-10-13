import Foundation

/// The two quality modes offered to the user.
public enum ConversionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Preserve decoded samples exactly where the target format allows it.
    /// Blocked (never silently downgraded) when exact preservation is impossible.
    case lossless
    /// Highest feasible quality within the target format's limits. May be lossy.
    case highestQuality

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lossless: return "Lossless"
        case .highestQuality: return "Highest Quality"
        }
    }

    public var subtitle: String {
        switch self {
        case .lossless:
            return "Preserve image data exactly. Conversion is blocked when the target cannot preserve it."
        case .highestQuality:
            return "Best quality the target format allows. Lossy targets may change pixel data."
        }
    }
}

/// How metadata is handled in the output.
public enum MetadataPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case keep
    case removeLocation
    case remove

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keep: return "Keep Metadata"
        case .removeLocation: return "Remove Location"
        case .remove: return "Remove Metadata"
        }
    }
}

/// What to do when the source has more frames/pages than the target supports.
public enum FramePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Extract every frame/page into separate files.
    case exportAll
    /// Use only the first frame/page.
    case firstOnly
    /// Requires an explicit user choice before conversion proceeds.
    case undecided

    public var id: String { rawValue }
}

/// Alpha handling when the target cannot store transparency.
public enum AlphaBackground: Equatable, Sendable {
    case black
    case white
    case custom(red: Double, green: Double, blue: Double, alpha: Double)

    /// Round-trippable storage form used by the app's preferences.
    public var storageString: String {
        switch self {
        case .black: return "black"
        case .white: return "white"
        case .custom(let r, let g, let b, let a):
            return "custom:\(r),\(g),\(b),\(a)"
        }
    }

    /// Parses `storageString`, falling back to white for anything unrecognized.
    public static func fromStorage(_ string: String?) -> AlphaBackground {
        guard let string else { return .white }
        if string == "black" { return .black }
        if string.hasPrefix("custom:") {
            let parts = string.dropFirst("custom:".count).split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 { return .custom(red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3]) }
            if parts.count == 3 { return .custom(red: parts[0], green: parts[1], blue: parts[2], alpha: 1) }
        }
        return .white
    }
}

/// Complete, user-visible settings for a conversion run.
public struct ConversionSettings: Equatable, Sendable {
    public var mode: ConversionMode
    public var metadataPolicy: MetadataPolicy
    public var framePolicy: FramePolicy
    public var alphaBackground: AlphaBackground

    /// Render resolution for PDF pages, in DPI. conv3rt's default (144 = 2× of
    /// a 72-DPI page) is a choice, not a fixed product decision.
    public var pdfDPI: Double
    /// Rasterization scale for SVG, relative to the file's intrinsic size.
    public var svgScale: Double
    /// When true, outputs mirror the source sub-folder structure under the
    /// chosen output folder.
    public var keepFolderStructure: Bool

    public init(
        mode: ConversionMode = .lossless,
        metadataPolicy: MetadataPolicy = .keep,
        framePolicy: FramePolicy = .undecided,
        alphaBackground: AlphaBackground = .white,
        pdfDPI: Double = 144,
        svgScale: Double = 2.0,
        keepFolderStructure: Bool = false
    ) {
        self.mode = mode
        self.metadataPolicy = metadataPolicy
        self.framePolicy = framePolicy
        self.alphaBackground = alphaBackground
        self.pdfDPI = pdfDPI
        self.svgScale = svgScale
        self.keepFolderStructure = keepFolderStructure
    }
}
