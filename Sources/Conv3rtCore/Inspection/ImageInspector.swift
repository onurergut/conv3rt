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
            return try inspectImageIO(source: source, uti: uti, url: url,
                                      fileSize: fileSize, declaredUTI: declaredUTI)
        }
        throw InspectionError.unsupportedType(declaredUTI)
    }

    private func inspectImageIO(source: CGImageSource, uti: String, url: URL,
                                fileSize: Int64, declaredUTI: String?) throws -> ImageInfo {
        let count = CGImageSourceGetCount(source)

        // Top-level properties (first image).
        let topProps = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any]) ?? [:]
        let frame0Props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? topProps

        let width = int(frame0Props[kCGImagePropertyPixelWidth] ?? topProps[kCGImagePropertyPixelWidth]) ?? 0
        let height = int(frame0Props[kCGImagePropertyPixelHeight] ?? topProps[kCGImagePropertyPixelHeight]) ?? 0
        let depth = int(frame0Props[kCGImagePropertyDepth]) ?? 8
        let orientation = int(frame0Props[kCGImagePropertyOrientation])
        let colorModel = colorModelString(frame0Props[kCGImagePropertyColorModel])
        let profileName = frame0Props[kCGImagePropertyProfileName] as? String
        let hasAlpha = (frame0Props[kCGImagePropertyHasAlpha] as? Bool) ?? false

        let exif = frame0Props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = frame0Props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let iptc = frame0Props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        // XMP has no public Image I/O dictionary constant; read the literal key.
        let xmp = frame0Props["XMP" as CFString] as? [CFString: Any]

        // Frame/page structure.
        let gifDict = frame0Props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let pngDict = frame0Props[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        var durations: [Double] = []
        for i in 0..<count {
            guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] else { continue }
            if let g = p[kCGImagePropertyGIFDictionary] as? [CFString: Any],
               let d = double(g[kCGImagePropertyGIFDelayTime]) {
                durations.append(d)
            } else if let w = p[kCGImagePropertyWebPDictionary] as? [CFString: Any],
                      let d = double(w[kCGImagePropertyWebPDelayTime]) {
                durations.append(d)
            }
        }
        let loopCount = int(gifDict?[kCGImagePropertyGIFLoopCount])
            ?? int(pngDict?[kCGImagePropertyAPNGLoopCount])

        // Formats whose multi-image containers are animations, not page stacks.
        // WebP/AVIF/JPEG XL carry animation without the GIF delay keys, so a
        // multi-image file of these types is treated as animated regardless.
        let animatedFamily = UTTypeBridge.conformance(uti, toIdentifier: "com.compuserve.gif")
            || UTTypeBridge.conformance(uti, toIdentifier: "public.heics")
            || UTTypeBridge.conformance(uti, toIdentifier: "org.webmproject.webp")
            || UTTypeBridge.conformance(uti, toIdentifier: "public.avif")
            || UTTypeBridge.conformance(uti, toIdentifier: "public.jpeg-xl")
        let isAnimatedType = count > 1 && (animatedFamily || durations.count > 1)

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
            canvasWidth: width,
            canvasHeight: height,
            bitsPerComponent: depth,
            bitsPerPixel: depth * channelCount(colorModel: colorModel, hasAlpha: hasAlpha),
            hasAlpha: hasAlpha,
            colorModel: colorModel,
            colorSpaceName: profileName,
            hasColorProfile: (profileName?.isEmpty == false),
            exifOrientation: orientation,
            hasEXIF: exif?.isEmpty == false,
            hasGPS: gps?.isEmpty == false,
            hasIPTC: iptc?.isEmpty == false,
            hasXMP: xmp?.isEmpty == false
        )
    }

    /// Cheap check: can conv3rt open and decode this file at all?
    public func isReadable(url: URL) -> Bool {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0 {
            return true
        }
        let kind = SourceProviderFactory.detectKind(url: url)
        if kind != .imageIO, let provider = SourceProviderFactory.make(url: url) {
            return provider.image(at: 0) != nil
        }
        return false
    }

    /// Builds `ImageInfo` for a source that Image I/O cannot type (PDF, SVG).
    private func inspectProvider(_ provider: any SourceFrameProvider, url: URL, uti: String?,
                                 declaredUTI: String?, fileSize: Int64) throws -> ImageInfo {
        guard let first = provider.image(at: 0) else {
            throw InspectionError.corrupted("The document produced no image.")
        }
        // Use the rendered image's dimensions as authoritative.
        let width = first.width
        let height = first.height
        let alpha: Bool
        switch first.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: alpha = true
        default: alpha = false
        }
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
            canvasWidth: width,
            canvasHeight: height,
            bitsPerComponent: first.bitsPerComponent,
            bitsPerPixel: first.bitsPerPixel,
            hasAlpha: alpha,
            colorModel: "RGB",
            colorSpaceName: first.colorSpace?.name as String?,
            hasColorProfile: first.colorSpace != nil,
            exifOrientation: nil,
            hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false
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

    private func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
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
