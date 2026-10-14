import Foundation
import ImageIO

/// Reads the true structure of a source file from its content, not its name.
public struct ImageInspector: Sendable {

    public init() {}

    /// Inspects a file using its real content, not its extension. Uses Image I/O
    /// first, then falls back to PDFKit/AppKit for PDF and SVG.
    public func inspect(url: URL) throws -> ImageInfo {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let ext = url.pathExtension.lowercased()
        let declaredUTI = ext.isEmpty ? nil : UTTypeBridge.identifier(forExtension: ext)

        // PDF and SVG are resolution-independent; Image I/O cannot give them
        // real pixel dimensions, so they go through PDFKit/AppKit first.
        let kind = SourceProviderFactory.detectKind(url: url)
        if kind != .imageIO, let provider = SourceProviderFactory.make(url: url) {
            return try inspectProvider(provider, url: url,
                                       uti: SourceProviderFactory.uti(for: kind) ?? declaredUTI,
                                       declaredUTI: declaredUTI, fileSize: fileSize)
        }

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let uti = CGImageSourceGetType(source) as String?,
           CGImageSourceGetCount(source) > 0 {
            guard uti != "com.adobe.pdf", uti != "public.svg-image" else {
                throw InspectionError.corrupted("The document could not be opened within resource limits.")
            }
            return try inspectImageIO(source: source, uti: uti, url: url,
                                      fileSize: fileSize, declaredUTI: declaredUTI)
        }
        throw InspectionError.unsupportedType(declaredUTI)
    }

    private func inspectImageIO(source: CGImageSource, uti: String, url: URL,
                                fileSize: Int64, declaredUTI: String?) throws -> ImageInfo {
        let count = CGImageSourceGetCount(source)

        let topProps = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any]) ?? [:]
        let frame0Props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? topProps
        let width = int(frame0Props[kCGImagePropertyPixelWidth] ?? topProps[kCGImagePropertyPixelWidth]) ?? 0
        let height = int(frame0Props[kCGImagePropertyPixelHeight] ?? topProps[kCGImagePropertyPixelHeight]) ?? 0
        let orientation = int(frame0Props[kCGImagePropertyOrientation])
        var depth = 0
        var pixelDepth = 0
        var hasAlpha = false
        var colorModel = colorModelString(frame0Props[kCGImagePropertyColorModel])
        var profileName: String?
        var hasEXIF = hasMetadata(topProps, key: kCGImagePropertyExifDictionary)
        var hasGPS = hasMetadata(topProps, key: kCGImagePropertyGPSDictionary)
        var hasIPTC = hasMetadata(topProps, key: kCGImagePropertyIPTCDictionary)
        var hasXMP = hasMetadata(topProps, key: "XMP" as CFString)
        var canvasWidth = width
        var canvasHeight = height
        var decodedBytes = 0.0
        var durations: [Double] = []
        for i in 0..<count {
            guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] else {
                throw InspectionError.corrupted("Frame \(i + 1) has no readable image properties.")
            }
            let frameWidth = int(p[kCGImagePropertyPixelWidth]) ?? 0
            let frameHeight = int(p[kCGImagePropertyPixelHeight]) ?? 0
            let frameDepth = max(int(p[kCGImagePropertyDepth]) ?? 8, 1)
            let frameAlpha = (p[kCGImagePropertyHasAlpha] as? Bool) ?? false
            let frameModel = colorModelString(p[kCGImagePropertyColorModel])
            let bits = frameDepth.multipliedReportingOverflow(by: channelCount(colorModel: frameModel, hasAlpha: frameAlpha))
            let framePixelDepth = bits.overflow ? Int.max : bits.partialValue
            depth = max(depth, frameDepth)
            pixelDepth = max(pixelDepth, framePixelDepth)
            hasAlpha = hasAlpha || frameAlpha
            if frameModel == "CMYK" { colorModel = frameModel }
            if profileName == nil, let name = p[kCGImagePropertyProfileName] as? String, !name.isEmpty {
                profileName = name
            }
            hasEXIF = hasEXIF || hasMetadata(p, key: kCGImagePropertyExifDictionary)
            hasGPS = hasGPS || hasMetadata(p, key: kCGImagePropertyGPSDictionary)
            hasIPTC = hasIPTC || hasMetadata(p, key: kCGImagePropertyIPTCDictionary)
            hasXMP = hasXMP || hasMetadata(p, key: "XMP" as CFString) || hasXMPMetadata(source, index: i)
            canvasWidth = max(canvasWidth, frameWidth)
            canvasHeight = max(canvasHeight, frameHeight)
            // Header dimensions/depth avoid decoding an oversized image just
            // to reject it. Each frame contributes its own footprint.
            if frameWidth <= 0 || frameHeight <= 0 { decodedBytes = .infinity }
            else { decodedBytes += Double(frameWidth) * Double(frameHeight) * ceil(Double(framePixelDepth) / 8) }
            if let delay = SourceAnimation.duration(in: p) { durations.append(delay) }
        }
        let loopCount = SourceAnimation.loopCount(in: topProps) ?? SourceAnimation.loopCount(in: frame0Props)
        let isAnimatedType = SourceAnimation.isAnimated(uti: uti, count: count, properties: topProps)
            || SourceAnimation.isAnimated(uti: uti, count: count, properties: frame0Props)
        let frameCount = isAnimatedType ? count : 1
        let pageCount = isAnimatedType ? 1 : count

        return ImageInfo(
            url: url,
            detectedUTI: uti,
            declaredUTI: declaredUTI,
            fileSize: fileSize,
            pixelWidth: width,
            pixelHeight: height,
            frameCount: frameCount,
            pageCount: pageCount,
            frameDurations: isAnimatedType ? durations : [],
            loopCount: isAnimatedType ? loopCount : nil,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            bitsPerComponent: depth,
            bitsPerPixel: pixelDepth,
            hasAlpha: hasAlpha,
            colorModel: colorModel,
            colorSpaceName: profileName,
            hasColorProfile: (profileName?.isEmpty == false),
            exifOrientation: orientation,
            hasEXIF: hasEXIF,
            hasGPS: hasGPS,
            hasIPTC: hasIPTC,
            hasXMP: hasXMP,
            decodedByteCount: decodedBytes
        )
    }

    /// Cheap check that the file has a supported source representation.
    public func isReadable(url: URL) -> Bool {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let uti = CGImageSourceGetType(source) as String?, CGImageSourceGetCount(source) > 0,
           uti != "com.adobe.pdf", uti != "public.svg-image" {
            return true
        }
        let kind = SourceProviderFactory.detectKind(url: url)
        if kind != .imageIO, let provider = SourceProviderFactory.make(url: url) {
            if provider is SVGFrameProvider { return true }
            if let provider = provider as? any InspectableFrameProvider {
                return provider.inspection(at: 0) != nil
            }
            return provider.image(at: 0) != nil
        }
        return false
    }

    /// Builds `ImageInfo` for a source that Image I/O cannot type (PDF, SVG).
    func inspectProvider(_ provider: any SourceFrameProvider, url: URL, uti: String?,
                                 declaredUTI: String?, fileSize: Int64) throws -> ImageInfo {
        func frame(at index: Int) -> FrameInspection? {
            if let provider = provider as? any InspectableFrameProvider {
                return provider.inspection(at: index)
            }
            return provider.image(at: index).map { FrameInspection(image: $0) }
        }
        guard let first = frame(at: 0) else {
            throw InspectionError.corrupted("The document produced no image.")
        }
        let width = first.width
        let height = first.height
        var depth = first.bitsPerComponent
        var pixelDepth = first.bitsPerPixel
        var alpha = false
        var canvasWidth = width
        var canvasHeight = height
        var decodedBytes = 0.0
        var profileName: String?
        for index in 0..<provider.frameCount {
            guard let inspected = index == 0 ? first : frame(at: index) else {
                throw InspectionError.corrupted("Page \(index + 1) could not be decoded.")
            }
            depth = max(depth, inspected.bitsPerComponent)
            pixelDepth = max(pixelDepth, inspected.bitsPerPixel)
            alpha = alpha || inspected.hasAlpha
            canvasWidth = max(canvasWidth, inspected.width)
            canvasHeight = max(canvasHeight, inspected.height)
            decodedBytes += Double(inspected.bytesPerRow) * Double(inspected.height)
            if profileName == nil { profileName = inspected.colorSpaceName }
        }
        // These builtin files store no ICC profile. The decoder supplies an
        // implicit color space for display, which is not an embedded profile.
        let carriesProfile = !["com.conv3rt.qoi", "com.conv3rt.pcx", "com.conv3rt.pfm"].contains(uti ?? "")
        let isPaged = provider.unitName == "page"
        return ImageInfo(
            url: url,
            detectedUTI: uti,
            declaredUTI: declaredUTI,
            fileSize: fileSize,
            pixelWidth: width,
            pixelHeight: height,
            frameCount: isPaged ? 1 : provider.frameCount,
            pageCount: isPaged ? provider.frameCount : (provider.frameCount > 1 ? provider.frameCount : 1),
            frameDurations: [],
            loopCount: nil,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            bitsPerComponent: depth,
            bitsPerPixel: pixelDepth,
            hasAlpha: alpha,
            colorModel: "RGB",
            colorSpaceName: profileName,
            hasColorProfile: carriesProfile && profileName != nil,
            exifOrientation: nil,
            hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false,
            decodedByteCount: decodedBytes
        )
    }

    // MARK: - Helpers

    private func channelCount(colorModel: String?, hasAlpha: Bool) -> Int {
        let base: Int
        switch colorModel {
        case "Gray": base = 1
        case "CMYK": base = 4
        default: base = 3
        }
        return base + (hasAlpha ? 1 : 0)
    }

    private func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private func hasMetadata(_ properties: [CFString: Any], key: CFString) -> Bool {
        (properties[key] as? [CFString: Any])?.isEmpty == false
    }

    private func hasXMPMetadata(_ source: CGImageSource, index: Int) -> Bool {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else { return false }
        return tags.contains { tag in
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
            let namespace = CGImageMetadataTagCopyNamespace(tag) as String? ?? ""
            // Image I/O also exposes native EXIF/TIFF fields through this API.
            // Other namespaces include standard and user-defined XMP schemas;
            // their XML prefix is arbitrary and cannot identify the schema.
            let native = ["http://ns.adobe.com/exif/1.0/", "http://ns.adobe.com/exif/1.0/aux/",
                          "http://ns.adobe.com/tiff/1.0/"]
            return ["xmp", "xmpRights", "xmpMM", "dc", "photoshop"].contains(prefix)
                || (!namespace.isEmpty && !native.contains(namespace))
        }
    }

    private func colorModelString(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        switch s {
        case String(kCGImagePropertyColorModelRGB): return "RGB"
        case String(kCGImagePropertyColorModelGray): return "Gray"
        case String(kCGImagePropertyColorModelCMYK): return "CMYK"
        case String(kCGImagePropertyColorModelLab): return "Lab"
        default: return s
        }
    }
}
