import Foundation
import ImageIO
import CoreGraphics
import Darwin

/// Result of converting a single source/plan.
public struct ConversionResult: Sendable {
    public let outputs: [URL]
    public let frameCount: Int
    public let isStructural: Bool
    public let notes: [String]
}

public enum ConversionError: Error, LocalizedError, Equatable, Sendable {
    case planBlocked(String)
    case sourceUnreadable
    case cannotDecodeFrame(Int)
    case encodeFailed(String)
    case verificationFailed(String)
    case canceled

    public var errorDescription: String? {
        switch self {
        case .planBlocked(let m): return m
        case .sourceUnreadable: return "The source image could not be decoded."
        case .cannotDecodeFrame(let i): return "Frame \(i + 1) could not be decoded."
        case .encodeFailed(let d): return "Encoding failed. \(d)"
        case .verificationFailed(let d): return "The output did not verify. \(d)"
        case .canceled: return "Conversion canceled."
        }
    }
}

/// Decodes frames and encodes them to the target format. Deterministic and
/// UI-free, so it can be unit-tested end to end.
public struct ConversionEngine: Sendable {

    public let quality: Double

    public init(quality: Double = 0.9) {
        self.quality = quality
    }

    /// Converts one source per its plan.
    /// - Parameters:
    ///   - plan: the planned conversion (must not be blocked).
    ///   - outputDirectory: destination folder (must be writable).
    ///   - namer: shared collision-free namer.
    ///   - verifier: output verifier.
    ///   - isCancelled: polled between frames; return true to abort.
    ///   - progress: fraction 0…1 for this job.
    @discardableResult
    public func convert(
        plan: ConversionPlan,
        outputDirectory: URL,
        namer: OutputNamer,
        verifier: OutputVerifier = OutputVerifier(),
        target: FormatCapability,
        isCancelled: @escaping () -> Bool = { false },
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ConversionResult {
        guard plan.status != .blocked else {
            throw ConversionError.planBlocked(plan.blockingChanges.first?.message ?? "Conversion is blocked.")
        }
        if isCancelled() { throw ConversionError.canceled }
        guard let provider = makeProvider(for: plan.source, settings: plan.settings) else {
            throw ConversionError.sourceUnreadable
        }

        let baseName = plan.source.url.deletingPathExtension().lastPathComponent
        let ext = target.fileExtensions.first ?? UTTypeBridge.preferredFilenameExtension(target.uti) ?? "img"
        let settings = plan.settings

        var outputs: [URL] = []
        var outputIdentities: [OutputIdentity] = []
        var notes: [String] = []
        var completed = false
        defer {
            if !completed {
                for (url, identity) in zip(outputs, outputIdentities) {
                    if OutputIdentity(url: url) == identity {
                        url.withUnsafeFileSystemRepresentation { path in
                            if let path { _ = unlink(path) }
                        }
                    }
                    namer.release(url)
                }
            }
        }

        // Decide frame indices.
        let total = provider.frameCount
        let frames: [Int]
        if plan.expandsFramesOrPages {
            frames = Array(0..<total)
        } else if settings.framePolicy == .firstOnly && total > 1 && !plan.expandsFramesOrPages {
            frames = [0]
        } else {
            frames = Array(0..<total)
        }

        if plan.expandsFramesOrPages {
            // One output file per frame/page.
            for (n, idx) in frames.enumerated() {
                if isCancelled() { throw ConversionError.canceled }
                let frameName = String(format: "%@-%@-%04d", baseName, provider.unitName, n + 1)
                let safe = try SafeOutput(directory: outputDirectory)
                defer { safe.cleanup() }
                try encodeSingleFrame(provider: provider, index: idx, to: safe.tempURL,
                                      target: target, settings: settings, isCancelled: isCancelled)
                try verifier.verify(url: safe.tempURL, expectedUTI: target.uti, expectedFrames: 1)
                if settings.mode == .lossless && !plan.isStructural {
                    try LosslessVerifier().verify(sourceProvider: provider, sourceInfo: plan.source,
                                                  sourceIndices: [idx], outputURL: safe.tempURL,
                                                  expectedOutputFrames: 1)
                }
                if isCancelled() { throw ConversionError.canceled }
                guard let identity = OutputIdentity(url: safe.tempURL) else {
                    throw ConversionError.encodeFailed("The temporary output could not be read.")
                }
                let finalURL = namer.uniqueURL(in: outputDirectory, baseName: frameName, fileExtension: ext)
                let placed = try safe.commit(to: finalURL, namer: namer, baseName: frameName, ext: ext)
                outputs.append(placed)
                outputIdentities.append(identity)
                progress?(Double(n + 1) / Double(frames.count))
            }
            notes.append("Exported \(frames.count) \(provider.unitName)s.")
        } else {
            // Single output, possibly with several frames.
            let safe = try SafeOutput(directory: outputDirectory)
            defer { safe.cleanup() }
            try encodeFrames(provider: provider, indices: frames, to: safe.tempURL,
                             target: target, settings: settings, isCancelled: isCancelled, progress: progress)
            try verifier.verify(url: safe.tempURL, expectedUTI: target.uti, expectedFrames: frames.count)
            if settings.mode == .lossless && !plan.isStructural {
                try LosslessVerifier().verify(sourceProvider: provider, sourceInfo: plan.source,
                                              sourceIndices: frames, outputURL: safe.tempURL,
                                              expectedOutputFrames: frames.count)
            }
            if isCancelled() { throw ConversionError.canceled }
            guard let identity = OutputIdentity(url: safe.tempURL) else {
                throw ConversionError.encodeFailed("The temporary output could not be read.")
            }
            let finalURL = namer.uniqueURL(in: outputDirectory, baseName: baseName, fileExtension: ext)
            let placed = try safe.commit(to: finalURL, namer: namer, baseName: baseName, ext: ext)
            outputs.append(placed)
            outputIdentities.append(identity)
        }

        if plan.isStructural {
            notes.append("Exported as a flattened raster image.")
        }
        completed = true
        progress?(1)
        return ConversionResult(outputs: outputs, frameCount: frames.count,
                                isStructural: plan.isStructural, notes: notes)
    }

    // MARK: - Provider

    private func makeProvider(for source: ImageInfo, settings: ConversionSettings)
        -> (any SourceFrameProvider)? {
        SourceProviderFactory.make(url: source.url, dpi: settings.pdfDPI, svgScale: settings.svgScale)
    }

    // MARK: - Encoding

    private func encodeFrames(provider: any SourceFrameProvider, indices: [Int], to url: URL,
                              target: FormatCapability, settings: ConversionSettings,
                              isCancelled: @escaping () -> Bool,
                              progress: (@Sendable (Double) -> Void)?) throws {
        if Self.isCustomCodec(target.id) {
            if isCancelled() { throw ConversionError.canceled }
            if indices.count > 1, Self.supportsAnimatedWrite(target.id) {
                try encodeCustomAnimated(provider: provider, indices: indices, to: url,
                                         target: target, settings: settings, isCancelled: isCancelled,
                                         progress: progress)
                return
            }
            guard indices.count == 1 else {
                throw ConversionError.encodeFailed("Animated \(target.displayName) output is not supported.")
            }
            try encodeCustomOne(provider: provider, index: indices[0], to: url,
                                target: target, settings: settings, isCancelled: isCancelled,
                                progress: progress.map { callback in { @Sendable p in callback(p * 0.9) } })
            return
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, target.uti as CFString,
                                                         indices.count, nil) else {
            throw ConversionError.encodeFailed("The encoder could not be created for \(target.displayName).")
        }
        applyContainerProperties(dest: dest, provider: provider, target: target, settings: settings)

        for (n, idx) in indices.enumerated() {
            if isCancelled() { throw ConversionError.canceled }
            guard let image = provider.image(at: idx) else {
                throw ConversionError.cannotDecodeFrame(idx)
            }
            let props = destinationProperties(from: provider.properties(at: idx),
                                              index: idx, provider: provider,
                                              target: target, settings: settings)
            let prepared = prepare(image, target: target, settings: settings)
            let frameProps = withQuality(props, target: target, settings: settings)
            addImage(prepared, to: dest, provider: provider, index: idx,
                     properties: frameProps, target: target, settings: settings)
            progress?(0.9 * Double(n + 1) / Double(max(indices.count, 1)))
        }

        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed("The encoder did not finalize the output.")
        }
    }

    private func encodeSingleFrame(provider: any SourceFrameProvider, index: Int, to url: URL,
                                   target: FormatCapability, settings: ConversionSettings,
                                   isCancelled: @escaping () -> Bool) throws {
        if isCancelled() { throw ConversionError.canceled }
        if Self.isCustomCodec(target.id) {
            try encodeCustomOne(provider: provider, index: index, to: url, target: target,
                                settings: settings, isCancelled: isCancelled)
            return
        }
        guard let image = provider.image(at: index) else {
            throw ConversionError.cannotDecodeFrame(index)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, target.uti as CFString, 1, nil) else {
            throw ConversionError.encodeFailed("The encoder could not be created for \(target.displayName).")
        }
        var props = destinationProperties(from: provider.properties(at: index), index: index,
                                          provider: provider, target: target, settings: settings)
        props = withQuality(props, target: target, settings: settings)
        let prepared = prepare(image, target: target, settings: settings)
        addImage(prepared, to: dest, provider: provider, index: index,
                 properties: props, target: target, settings: settings)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed("The encoder did not finalize the output.")
        }
    }

    /// Formats written by a bundled codec rather than Apple Image I/O.
    static func isCustomCodec(_ id: String) -> Bool {
        ["webp", "jxl", "avif", "qoi", "pcx", "pfm", "dds"].contains(id)
    }

    /// Bundled-codec targets that can write an animation into a single file.
    /// JPEG XL's libjxl can encode animation, but macOS Image I/O cannot read
    /// animated JPEG XL back (it reports a single frame), so the output would
    /// fail verification — JPEG XL animation is therefore not offered here.
    static func supportsAnimatedWrite(_ id: String) -> Bool {
        id == "webp"
    }

    /// Encodes one frame as a single-frame WebP, JPEG XL, QOI, PCX or PFM.
    private func encodeCustomOne(provider: any SourceFrameProvider, index: Int, to url: URL,
                                 target: FormatCapability, settings: ConversionSettings,
                                 isCancelled: @escaping () -> Bool,
                                 progress: (@Sendable (Double) -> Void)? = nil) throws {
        if isCancelled() { throw ConversionError.canceled }
        guard let image = provider.image(at: index) else {
            throw ConversionError.cannotDecodeFrame(index)
        }
        let prepared = prepare(image, target: target, settings: settings)
        let lossless = settings.mode == .lossless

        // WebP/JXL carry metadata through dedicated container chunks/boxes. Only
        // Image I/O-sourced frames can supply it; other providers have none.
        let (exif, xmp) = customMetadata(provider: provider, index: index, settings: settings)

        let data: Data
        switch target.id {
        case "webp":
            data = try WebPEncoder.encode(image: prepared, lossless: lossless, quality: quality,
                                          exif: exif, xmp: xmp, isCancelled: isCancelled, progress: progress)
        case "jxl":
            data = try JXLEncoder.encode(image: prepared, lossless: lossless, quality: quality,
                                         exif: exif, xmp: xmp)
        case "avif":
            // AVIF is a lossy target: `lossless` is ignored (the planner already
            // blocks lossless for AVIF). ICC is taken from the frame's color space.
            data = try AVIFEncoder.encode(image: prepared, lossless: lossless, quality: quality)
        case "qoi":
            data = try QOICodec.encode(prepared)
        case "pcx":
            data = try PCXCodec.encode(prepared)
        case "pfm":
            data = try NetpbmCodec.encodePFM(prepared)
        case "dds":
            data = try DDSCodec.encode(prepared)
        default:
            throw ConversionError.encodeFailed("No encoder for \(target.displayName).")
        }
        if isCancelled() { throw ConversionError.canceled }
        try data.write(to: url, options: .atomic)
    }

    /// Encodes all `indices` as one animated file with a bundled codec.
    private func encodeCustomAnimated(provider: any SourceFrameProvider, indices: [Int], to url: URL,
                                      target: FormatCapability, settings: ConversionSettings,
                                      isCancelled: @escaping () -> Bool,
                                      progress: (@Sendable (Double) -> Void)?) throws {
        var frames: [(image: CGImage, duration: Double)] = []
        frames.reserveCapacity(indices.count)
        var workingBytes = 0.0
        for (n, idx) in indices.enumerated() {
            if isCancelled() { throw ConversionError.canceled }
            guard let image = provider.image(at: idx) else {
                throw ConversionError.cannotDecodeFrame(idx)
            }
            let prepared = prepare(image, target: target, settings: settings)
            workingBytes += Double(prepared.bytesPerRow) * Double(prepared.height) * 3
            guard workingBytes <= RasterSizeGuard.maximumBytes else {
                throw ConversionError.encodeFailed("The animation is too large for the encoding buffers.")
            }
            frames.append((prepared, frameDuration(provider: provider, index: idx)))
            progress?(0.2 * Double(n + 1) / Double(max(indices.count, 1)))
        }

        let lossless = settings.mode == .lossless
        let (exif, xmp) = customMetadata(provider: provider, index: indices[0], settings: settings)
        let loop = loopCount(provider: provider)

        let data: Data
        switch target.id {
        case "webp":
            data = try WebPEncoder.encodeAnimated(frames: frames, lossless: lossless,
                                                  quality: quality, loopCount: loop,
                                                  exif: exif, xmp: xmp, isCancelled: isCancelled,
                                                  progress: progress.map { callback in { @Sendable p in callback(0.2 + p * 0.7) } })
        default:
            throw ConversionError.encodeFailed("Animated \(target.displayName) output is not supported.")
        }
        if isCancelled() { throw ConversionError.canceled }
        try data.write(to: url, options: .atomic)
    }

    /// Use original timing rather than the decoder's clamped playback delay.
    private func frameDuration(provider: any SourceFrameProvider, index: Int) -> Double {
        let duration = SourceAnimation.duration(in: provider.properties(at: index))
        return duration.flatMap { $0 > 0 ? $0 : nil } ?? 0.1
    }

    /// Animation loop count from the source, or 0 (repeat forever) when absent.
    private func loopCount(provider: any SourceFrameProvider) -> Int {
        (provider as? ImageIOFrameProvider)?.animationLoopCount
            ?? SourceAnimation.loopCount(in: provider.properties(at: 0)) ?? 0
    }

    /// Metadata blobs (raw EXIF + XMP packet) to embed in a custom-codec output,
    /// applying the settings' metadata policy. Only Image I/O sources supply
    /// metadata; every other provider yields none.
    private func customMetadata(provider: any SourceFrameProvider, index: Int,
                                settings: ConversionSettings)
        -> (exif: [UInt8]?, xmp: [UInt8]?) {
        switch settings.metadataPolicy {
        case .remove:
            return ((provider as? ImageIOFrameProvider)?.orientationEXIF(index: index), nil)
        case .keep, .removeLocation:
            let includeLocation = settings.metadataPolicy == .keep
            guard let io = provider as? ImageIOFrameProvider else { return (nil, nil) }
            return (io.metadataEXIF(includeLocation: includeLocation, index: index),
                    io.metadataXMP(includeLocation: includeLocation, index: index))
        }
    }

    // MARK: - Properties

    private func addImage(_ image: CGImage, to destination: CGImageDestination,
                          provider: any SourceFrameProvider, index: Int,
                          properties: [CFString: Any], target: FormatCapability,
                          settings: ConversionSettings) {
        let metadata = target.supportsMetadata
            ? (provider as? ImageIOFrameProvider)?.metadata(at: index, policy: settings.metadataPolicy) : nil
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
    }

    private func applyContainerProperties(dest: CGImageDestination, provider: any SourceFrameProvider,
                                          target: FormatCapability, settings: ConversionSettings) {
        // Preserve loop count for animated targets.
        guard provider.isAnimated, target.id == "gif" else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: loopCount(provider: provider)]] as CFDictionary)
    }

    private func destinationProperties(from sourceProps: [CFString: Any], index: Int,
                                       provider: any SourceFrameProvider, target: FormatCapability,
                                       settings: ConversionSettings) -> [CFString: Any] {
        var props = sourceProps

        // Never carry a stale thumbnail from the source.
        props.removeValue(forKey: "Thumbnail" as CFString)

        // Metadata policy.
        switch settings.metadataPolicy {
        case .keep:
            break
        case .removeLocation:
            props.removeValue(forKey: kCGImagePropertyGPSDictionary)
        case .remove:
            props.removeValue(forKey: kCGImagePropertyExifDictionary)
            props.removeValue(forKey: kCGImagePropertyGPSDictionary)
            props.removeValue(forKey: kCGImagePropertyIPTCDictionary)
            props.removeValue(forKey: "XMP" as CFString)
        }

        // If the target cannot store metadata, drop the dictionaries entirely so
        // no inconsistent fields are written.
        if !target.supportsMetadata {
            props.removeValue(forKey: kCGImagePropertyExifDictionary)
            props.removeValue(forKey: kCGImagePropertyGPSDictionary)
            props.removeValue(forKey: kCGImagePropertyIPTCDictionary)
            props.removeValue(forKey: "XMP" as CFString)
        }

        // Preserve per-frame delay for animated targets.
        if provider.isAnimated, target.id == "gif" {
            props[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime:
                frameDuration(provider: provider, index: index)]
        }

        return props
    }

    private func withQuality(_ props: [CFString: Any], target: FormatCapability,
                             settings: ConversionSettings) -> [CFString: Any] {
        guard settings.mode == .highestQuality, isLossyTarget(target.id) else { return props }
        var p = props
        p[kCGImageDestinationLossyCompressionQuality] = quality
        return p
    }

    private func isLossyTarget(_ id: String) -> Bool {
        ["jpeg", "heic", "avif", "webp", "jp2", "dds", "radiance"].contains(id)
    }

    // MARK: - Pixel preparation

    private func prepare(_ image: CGImage, target: FormatCapability,
                         settings: ConversionSettings) -> CGImage {
        var result = image

        // Flatten alpha for targets that cannot store it, in Highest Quality mode.
        let targetCanStoreAlpha = target.supportsAlpha
        if !targetCanStoreAlpha && hasAlpha(image) && settings.mode == .highestQuality {
            if let flattened = flatten(image, over: settings.alphaBackground) {
                result = flattened
            }
        }
        return result
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        default:
            return false
        }
    }

    private func flatten(_ image: CGImage, over bg: AlphaBackground) -> CGImage? {
        let width = image.width, height = image.height
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let depth = max(image.bitsPerComponent, 8)
        var bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        if depth == 16 { bitmapInfo.formUnion(.byteOrder16Little) }
        if depth == 32 { bitmapInfo.formUnion(.byteOrder32Little) }
        if image.bitmapInfo.contains(.floatComponents) { bitmapInfo.formUnion(.floatComponents) }
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: depth, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else { return nil }
        let (r, g, b, a) = rgba(bg)
        ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private func rgba(_ bg: AlphaBackground) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch bg {
        case .black: return (0, 0, 0, 1)
        case .white: return (1, 1, 1, 1)
        case .custom(let r, let g, let b, let a): return (CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a))
        }
    }
}

private struct OutputIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let birthSeconds: Int
    let birthNanoseconds: Int

    init?(url: URL) {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &info) } ?? -1
        }
        guard result == 0 else { return nil }
        device = info.st_dev
        inode = info.st_ino
        birthSeconds = info.st_birthtimespec.tv_sec
        birthNanoseconds = info.st_birthtimespec.tv_nsec
    }
}
