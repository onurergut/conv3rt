import Foundation
import ImageIO
import CoreGraphics

/// Frame provider backed by Image I/O. Used for every format macOS decodes,
/// including RAW, PSD, HEIC, WebP, AVIF, JPEG XL, GIF, TIFF and friends.
public struct ImageIOFrameProvider: SourceFrameProvider {

    private let source: CGImageSource
    public let frameCount: Int
    public let unitName: String
    public let isAnimated: Bool

    public init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        self.source = source
        let count = CGImageSourceGetCount(source)
        self.frameCount = count
        let uti = CGImageSourceGetType(source) as String? ?? ""
        let top = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any]) ?? [:]
        let first = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let animated = SourceAnimation.isAnimated(uti: uti, count: count, properties: top)
            || SourceAnimation.isAnimated(uti: uti, count: count, properties: first)
        self.isAnimated = animated
        self.unitName = animated ? "frame" : (count > 1 ? "page" : "frame")
    }

    public func image(at index: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateImageAtIndex(source, index, opts as CFDictionary)
    }

    public func properties(at index: Int) -> [CFString: Any] {
        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
    }

    /// Container-level properties (first image), used as metadata defaults.
    public func containerProperties() -> [CFString: Any] {
        (CGImageSourceCopyProperties(source, nil) as? [CFString: Any]) ?? [:]
    }

    public var animationLoopCount: Int? {
        SourceAnimation.loopCount(in: containerProperties()) ?? SourceAnimation.loopCount(in: properties(at: 0))
    }

    // MARK: - Metadata

    /// Returns the requested frame's metadata under the selected privacy policy.
    public func metadata(at index: Int, policy: MetadataPolicy) -> CGImageMetadata? {
        guard index >= 0, index < frameCount, policy != .remove,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { return nil }
        return policy == .removeLocation ? Self.strippingGPS(metadata) : metadata
    }

    /// The requested frame's merged metadata serialized as an XMP packet, or nil when
    /// the source carries none. When `includeLocation` is false, GPS tags are
    /// stripped so a "remove location" policy is honored.
    public func metadataXMP(includeLocation: Bool, index: Int = 0) -> [UInt8]? {
        guard let effective = metadata(at: index, policy: includeLocation ? .keep : .removeLocation) else { return nil }
        let tags = (CGImageMetadataCopyTags(effective) as? [CGImageMetadataTag]) ?? []
        guard !tags.isEmpty else { return nil }
        guard let data = CGImageMetadataCreateXMPData(effective, nil) else { return nil }
        return Array(data as Data)
    }

    /// The requested frame's raw EXIF payload (TIFF-structured, without the JPEG
    /// "Exif\0\0" header), suitable for a WebP "EXIF" chunk or a JPEG XL "Exif"
    /// box. Returns nil when the frame has no EXIF, GPS or display orientation.
    ///
    /// The payload is produced by writing the frame's metadata into a throwaway
    /// in-memory JPEG and extracting its APP1 segment — Image I/O offers no
    /// public EXIF serializer. When `includeLocation` is false the GPS dictionary
    /// is omitted.
    public func metadataEXIF(includeLocation: Bool, index: Int = 0) -> [UInt8]? {
        guard index >= 0, index < frameCount else { return nil }
        var props = properties(at: index)
        if !includeLocation { props.removeValue(forKey: kCGImagePropertyGPSDictionary) }

        let hasEXIF = !((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?.isEmpty ?? true)
        let hasGPS = !((props[kCGImagePropertyGPSDictionary] as? [CFString: Any])?.isEmpty ?? true)
        guard hasEXIF || hasGPS || Self.displayOrientation(in: props) != nil else { return nil }
        return Self.exifPayload(properties: props)
    }

    /// Display orientation is necessary to interpret the unrotated pixel data,
    /// even when private metadata is removed. This payload contains only that tag.
    public func orientationEXIF(index: Int = 0) -> [UInt8]? {
        guard index >= 0, index < frameCount,
              let orientation = Self.displayOrientation(in: properties(at: index)) else { return nil }
        // Little-endian TIFF with one IFD entry: Orientation (0x0112),
        // one SHORT value stored inline, followed by a null next-IFD offset.
        // Using a JPEG serializer here would add unrelated EXIF dimensions.
        return [
            0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00,
            UInt8(orientation), 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ]
    }

    private static func displayOrientation(in properties: [CFString: Any]) -> Int? {
        guard let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
              (2...8).contains(orientation) else { return nil }
        return orientation
    }

    private static func exifPayload(properties: [CFString: Any]) -> [UInt8]? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil),
              let pixel = Self.onePixelImage() else { return nil }
        CGImageDestinationAddImage(dest, pixel, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Self.extractEXIFPayload(Data(referencing: data))
    }

    /// Makes a mutable copy with every GPS/EXIF-GPS tag removed, or nil if a
    /// copy cannot be made.
    private static func strippingGPS(_ md: CGImageMetadata) -> CGImageMetadata? {
        guard let mutable = CGImageMetadataCreateMutableCopy(md) else { return nil }
        let tags = (CGImageMetadataCopyTags(mutable) as? [CGImageMetadataTag]) ?? []
        for tag in tags {
            let name = (CGImageMetadataTagCopyName(tag) as String?) ?? ""
            let prefix = (CGImageMetadataTagCopyPrefix(tag) as String?) ?? ""
            let namespace = (CGImageMetadataTagCopyNamespace(tag) as String?) ?? ""
            let isGPS = name.contains("GPS") || prefix.lowercased() == "gps"
                || namespace.lowercased().contains("gps")
            if isGPS, !prefix.isEmpty, !name.isEmpty {
                _ = CGImageMetadataRemoveTagWithPath(mutable, nil, "\(prefix):\(name)" as CFString)
            }
        }
        return mutable
    }

    /// A 1×1 sRGB image used only as the carrier when serializing metadata to a
    /// throwaway JPEG.
    private static func onePixelImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    /// Scans a JPEG for an APP1 "Exif\0\0" segment and returns the EXIF payload
    /// that follows the 6-byte header.
    private static func extractEXIFPayload(_ jpeg: Data) -> [UInt8]? {
        let bytes = [UInt8](jpeg)
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { break }
            let marker = bytes[i + 1]
            if marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
                i += 2; continue
            }
            if marker == 0xDA || marker == 0xD9 { break }       // start of scan / end
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if length < 2 || i + 2 + length > bytes.count { break }
            if marker == 0xE1 {
                let seg = i + 4
                let end = i + 2 + length
                if end - seg >= 6,
                   bytes[seg] == 0x45, bytes[seg + 1] == 0x78, bytes[seg + 2] == 0x69,
                   bytes[seg + 3] == 0x66, bytes[seg + 4] == 0x00, bytes[seg + 5] == 0x00 {
                    return Array(bytes[(seg + 6)..<end])
                }
            }
            i += 2 + length
        }
        return nil
    }
}
