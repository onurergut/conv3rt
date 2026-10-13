import Foundation

/// Everything conv3rt learned about a source file by actually decoding its
/// header and image structure — never by trusting the file extension.
public struct ImageInfo: Equatable, Sendable {
    public let url: URL
    /// UTI reported by Image I/O after reading the content (nil if unrecognized).
    public let detectedUTI: String?
    /// UTI the file extension claims (may disagree with `detectedUTI`).
    public let declaredUTI: String?
    public let fileSize: Int64

    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Number of images/frames in the container (>= 1).
    public let frameCount: Int
    /// Number of pages (TIFF/PDF/ICO/ICNS), else 1.
    public let pageCount: Int
    /// Seconds per frame, when the container is animated.
    public let frameDurations: [Double]
    public let loopCount: Int?
    public let canvasWidth: Int
    public let canvasHeight: Int

    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let hasAlpha: Bool
    public let colorModel: String?
    public let colorSpaceName: String?
    public let hasColorProfile: Bool
    public let exifOrientation: Int?

    public let hasEXIF: Bool
    public let hasGPS: Bool
    public let hasIPTC: Bool
    public let hasXMP: Bool

    /// Sum of each inspected frame/page's decoded footprint. Nil for callers
    /// that have only summary dimensions and need a conservative estimate.
    public let decodedByteCount: Double?

    public init(url: URL, detectedUTI: String?, declaredUTI: String?, fileSize: Int64,
                pixelWidth: Int, pixelHeight: Int, frameCount: Int, pageCount: Int,
                frameDurations: [Double], loopCount: Int?, canvasWidth: Int, canvasHeight: Int,
                bitsPerComponent: Int, bitsPerPixel: Int, hasAlpha: Bool, colorModel: String?,
                colorSpaceName: String?, hasColorProfile: Bool, exifOrientation: Int?,
                hasEXIF: Bool, hasGPS: Bool, hasIPTC: Bool, hasXMP: Bool,
                decodedByteCount: Double? = nil) {
        self.url = url
        self.detectedUTI = detectedUTI
        self.declaredUTI = declaredUTI
        self.fileSize = fileSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frameCount = frameCount
        self.pageCount = pageCount
        self.frameDurations = frameDurations
        self.loopCount = loopCount
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.hasAlpha = hasAlpha
        self.colorModel = colorModel
        self.colorSpaceName = colorSpaceName
        self.hasColorProfile = hasColorProfile
        self.exifOrientation = exifOrientation
        self.hasEXIF = hasEXIF
        self.hasGPS = hasGPS
        self.hasIPTC = hasIPTC
        self.hasXMP = hasXMP
        self.decodedByteCount = decodedByteCount
    }

    /// Whether the extension disagrees with the detected content type.
    public var extensionMismatch: Bool {
        guard let declaredUTI, let detectedUTI else { return false }
        if declaredUTI == detectedUTI { return false }
        // A JPEG named .jpg reports public.jpeg either way; a real mismatch is
        // when the declared type does not conform to the detected one.
        return !UTTypeBridge.conformance(detectedUTI, toIdentifier: declaredUTI)
            && !UTTypeBridge.conformance(declaredUTI, toIdentifier: detectedUTI)
    }

    /// True when the source carries more than one animation frame. (Page stacks
    /// such as multi-page TIFF set `pageCount`, not `frameCount`.)
    public var isAnimated: Bool { frameCount > 1 }
    public var totalDuration: Double { frameDurations.reduce(0, +) }

    public var pixelDescription: String {
        pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth) × \(pixelHeight)" : "—"
    }
}

/// Errors raised while inspecting a source.
public enum InspectionError: Error, LocalizedError, Sendable {
    case unreadable
    case unsupportedType(String?)
    case corrupted(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be opened."
        case .unsupportedType(let uti): return "Unsupported image format" + (uti.map { " (\($0))" } ?? "") + "."
        case .corrupted(let d): return "The image appears to be corrupted. \(d)"
        }
    }
}
