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
}

/// Complete, user-visible settings for a conversion run.
public struct ConversionSettings: Equatable, Sendable {
    public var mode: ConversionMode
    public var metadataPolicy: MetadataPolicy
    public var framePolicy: FramePolicy
    public var alphaBackground: AlphaBackground

    public init(
        mode: ConversionMode = .lossless,
        metadataPolicy: MetadataPolicy = .keep,
        framePolicy: FramePolicy = .undecided,
        alphaBackground: AlphaBackground = .white
    ) {
        self.mode = mode
        self.metadataPolicy = metadataPolicy
        self.framePolicy = framePolicy
        self.alphaBackground = alphaBackground
    }
}
