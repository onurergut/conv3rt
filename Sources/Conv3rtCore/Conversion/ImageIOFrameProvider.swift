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
        self.frameCount = CGImageSourceGetCount(source)
        let uti = CGImageSourceGetType(source) as String? ?? ""
        let animated = UTTypeBridge.conformance(uti, toIdentifier: "com.compuserve.gif")
            || UTTypeBridge.conformance(uti, toIdentifier: "public.heics")
        self.isAnimated = animated
        self.unitName = animated ? "frame" : (CGImageSourceGetCount(source) > 1 ? "page" : "frame")
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

    // MARK: - Metadata for custom codecs (WebP / JPEG XL)

    /// The first frame's merged metadata serialized as an XMP packet, or nil when
    /// the source carries none. When `includeLocation` is false, GPS tags are
    /// stripped so a "remove location" policy is honored.
    public func metadataXMP(includeLocation: Bool) -> [UInt8]? {
        guard let md = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return nil }
        let tags = (CGImageMetadataCopyTags(md) as? [CGImageMetadataTag]) ?? []
        guard !tags.isEmpty else { return nil }

        let effective: CGImageMetadata
        if includeLocation {
            effective = md
        } else {
            guard let stripped = Self.strippingGPS(md) else { return nil }
            effective = stripped
        }
        guard let data = CGImageMetadataCreateXMPData(effective, nil) else { return nil }
        return Array(data as Data)
    }

    /// The first frame's raw EXIF payload (TIFF-structured, without the JPEG
    /// "Exif\0\0" header), suitable for a WebP "EXIF" chunk or a JPEG XL "Exif"
    /// box. Returns nil when the frame has neither EXIF nor GPS.
    ///
    /// The payload is produced by writing the frame's metadata into a throwaway
    /// in-memory JPEG and extracting its APP1 segment — Image I/O offers no
    /// public EXIF serializer. When `includeLocation` is false the GPS dictionary
    /// is omitted.
    public func metadataEXIF(includeLocation: Bool) -> [UInt8]? {
        var props = properties(at: 0)
        if !includeLocation { props.removeValue(forKey: kCGImagePropertyGPSDictionary) }

        let hasEXIF = !((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?.isEmpty ?? true)
        let hasGPS = !((props[kCGImagePropertyGPSDictionary] as? [CFString: Any])?.isEmpty ?? true)
        guard hasEXIF || hasGPS else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil),
              let pixel = Self.onePixelImage() else { return nil }
        CGImageDestinationAddImage(dest, pixel, props as CFDictionary)
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
