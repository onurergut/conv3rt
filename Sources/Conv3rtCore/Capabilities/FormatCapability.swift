import Foundation

/// Who provides the codec used to read/write a format.
public enum CodecProvider: String, Codable, Hashable, Sendable {
    /// Apple Image I/O (built into macOS).
    case imageIO
    /// Apple PDFKit / Core Graphics PDF.
    case pdfKit
    /// A bundled third-party codec library.
    case bundled
    /// Implemented directly in conv3rt.
    case builtin
}

/// How confident we are about a capability claim.
public enum Evidence: String, Codable, Hashable, Sendable {
    /// Verified by an executable unit/integration test in this repository.
    case tested
    /// Verified manually against real files during development.
    case verified
    /// Known from Apple documentation / headers but not re-verified here.
    case documented
    /// Believed true but not yet verified. Surfaced to the user as a caveat.
    case unverified
}

/// A condition that must hold for a conversion to be genuinely lossless for a
/// given format pair. These are *data-preserving* conditions, not quality
/// sliders.
public enum LosslessCondition: String, Codable, Hashable, Sendable {
    /// Source has no alpha, or target preserves alpha exactly.
    case alphaPreserved
    /// Source bit depth is representable by the target without reduction.
    case bitDepthPreserved
    /// Color profile is carried through unchanged (or not needed).
    case colorProfilePreserved
    /// No chroma subsampling is applied.
    case noChromaSubsampling
    /// Every distinct source color fits the target palette.
    case paletteFits
    /// Animation timing is preserved exactly.
    case animationPreserved
    /// Multipage structure is preserved exactly.
    case multipagePreserved
    /// Sample values round-trip exactly (integer, same bit depth).
    case exactSamples
    /// Conversion path is structurally lossy (RAW/PSD/SVG/PDF rasterization).
    case notStructural
}

/// A single format/codec entry in the capability registry.
public struct FormatCapability: Identifiable, Hashable, Sendable {
    /// Stable identifier, e.g. "jpeg".
    public let id: String
    /// Uniform Type Identifier, e.g. "public.jpeg".
    public let uti: String
    /// Human-readable name shown in the UI.
    public let displayName: String
    /// File extensions normally associated with this format (lowercase, no dot).
    public let fileExtensions: [String]

    public var provider: CodecProvider = .imageIO
    /// Minimum macOS version string this codec is known to require, if any.
    public var minimumSystem: String?

    /// Whether Image I/O (or the runtime) reports this as a readable source type.
    public var canRead: Bool = false
    /// Whether the runtime reports this as a writable destination type.
    public var canWrite: Bool = false

    /// Bit depths the format can represent (e.g. [8, 16]).
    public var bitDepths: [Int] = [8]
    public var supportsAlpha: Bool = false
    public var supportsAnimation: Bool = false
    public var supportsMultiPage: Bool = false
    public var supportsColorProfile: Bool = false
    public var supportsMetadata: Bool = false
    /// Whether a genuinely lossless encode path exists (subject to `losslessConditions`).
    public var hasLosslessPath: Bool = false

    /// Conditions required for a lossless conversion *into* this format.
    public var losslessConditions: [LosslessCondition] = []
    /// Known limitations, shown in the UI and docs.
    public var limitations: [String] = []
    /// Whether this format is a "complex source" that is only exported as a raster image.
    public var isComplexSource: Bool = false

    public var evidence: Evidence = .documented

    public init(
        id: String,
        uti: String,
        displayName: String,
        fileExtensions: [String],
        provider: CodecProvider = .imageIO
    ) {
        self.id = id
        self.uti = uti
        self.displayName = displayName
        self.fileExtensions = fileExtensions
        self.provider = provider
    }

    /// A capability you can actually convert *into* (write is real and usable).
    public var isUsableDestination: Bool { canWrite }

    /// A capability you can ingest (read is real and usable).
    public var isUsableSource: Bool { canRead }
}
