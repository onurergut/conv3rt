import Foundation

/// Turns a source + target + settings into a `ConversionPlan` describing what
/// will be preserved and what will be lost, and whether the conversion can run
/// under the chosen mode.
///
/// The planner is pure (no I/O beyond the `ImageInfo` it is handed), so it is
/// fully unit-testable.
public struct ConversionPlanner: Sendable {

    private let registry: CapabilityRegistry
    /// Refuse inputs whose decoded size would exceed this. Protects against
    /// decompression bombs and absurd dimensions. Default 4 GiB.
    private let resourceLimitBytes: Double

    public init(registry: CapabilityRegistry = .shared,
                resourceLimitBytes: Double = 4 * 1024 * 1024 * 1024) {
        self.registry = registry
        self.resourceLimitBytes = resourceLimitBytes
    }

    public func plan(source: ImageInfo, target: FormatCapability,
                     settings: ConversionSettings) -> ConversionPlan {
        var changes: [FeatureChange] = []
        var isStructural = false
        let lossless = settings.mode == .lossless
        let sourceCap = source.detectedUTI.flatMap { registry.capability(uti: $0) }

        // --- Target availability -------------------------------------------------
        guard target.canWrite else {
            changes.append(.init(severity: .blocking,
                                 message: "\(target.displayName) is not a supported output format on this system.",
                                 code: "target.notWritable"))
            return build(source, target, settings, changes, isStructural: false, expands: false)
        }

        // --- Resource guard (decompression bombs / absurd dimensions) ------------
        if source.pixelWidth <= 0 || source.pixelHeight <= 0 {
            changes.append(.init(severity: .blocking,
                                 message: "The image has invalid dimensions.",
                                 code: "resource.invalid"))
        } else if decodedBytes(source) > resourceLimitBytes {
            changes.append(.init(severity: .blocking,
                                 message: "Image too large for available resources.",
                                 code: "resource.tooLarge"))
        }
        if target.id == "webp" && (max(source.pixelWidth, source.canvasWidth) > 16_383
                                  || max(source.pixelHeight, source.canvasHeight) > 16_383) {
            changes.append(.init(severity: .blocking,
                                 message: "WebP supports images up to 16,383 pixels on each side.",
                                 code: "target.dimensions"))
        }

        // --- CMYK / exotic color models -----------------------------------------
        if source.colorModel == "CMYK" {
            let targetKeepsCMYK = ["jpeg", "tiff", "jp2"].contains(target.id)
            if !targetKeepsCMYK {
                changes.append(.init(severity: lossless ? .blocking : .warning,
                                     message: "CMYK color will be converted to RGB for \(target.displayName).",
                                     code: "color.cmyk"))
            }
        }

        // --- Complex sources (RAW / PSD / SVG / PDF) -----------------------------
        if sourceCap?.isComplexSource == true || isComplexByUTI(source.detectedUTI) {
            isStructural = true
            let name = sourceCap?.displayName ?? "This source"
            if lossless {
                // Rasterizing RAW/PSD/SVG/PDF cannot preserve the original
                // structure, so it is never a Lossless conversion.
                changes.append(.init(severity: .blocking,
                                     message: "\(name) is exported as a flattened raster image; its original structure is lost. Switch to Highest Quality.",
                                     code: "structural.export"))
            } else {
                changes.append(.init(severity: .warning,
                                     message: "\(name) is exported as a flattened raster image; its original structure is not preserved.",
                                     code: "structural.export"))
            }
        }

        // --- Animation / multipage ----------------------------------------------
        let total = max(source.frameCount, source.pageCount)
        let kind = source.isAnimated ? "frames" : "pages"
        let targetPreserves = source.isAnimated ? target.supportsAnimation
                                                : (source.pageCount > 1 ? target.supportsMultiPage : true)
        var expands = false
        func describePreservation() {
            if source.isAnimated && !timingIsRepresentable(source, target: target) {
                changes.append(.init(severity: lossless ? .blocking : .warning,
                                     message: "Animation timing or loop count cannot be preserved exactly. Highest Quality may use fallback timing or round frame durations.",
                                     code: "animation.timing"))
            } else {
                let message = source.isAnimated
                    ? "All \(total) frames and their timing will be preserved."
                    : "All \(total) pages will be preserved."
                changes.append(.init(severity: .info, message: message, code: "frames.preserved"))
            }
        }
        if total > 1 {
            switch settings.framePolicy {
            case .undecided:
                if !targetPreserves {
                    let message = source.isAnimated && lossless
                        ? "\(target.displayName) cannot preserve this animation. Choose an animation format, or switch to Highest Quality to export individual frames."
                        : "\(target.displayName) cannot store all \(total) \(kind). Choose to export all \(kind) or use the first one."
                    changes.append(.init(severity: .blocking,
                                         message: message,
                                         code: "frames.decisionRequired"))
                } else {
                    describePreservation()
                }
            case .firstOnly:
                // Discarding frames/pages is a content loss independent of
                // whether the target could have held them, so it can never be
                // offered as Lossless.
                let sev: ChangeSeverity = lossless ? .blocking : .warning
                let losslessAdvice = source.isAnimated && !targetPreserves
                    ? "Switch to Highest Quality."
                    : "Switch to Highest Quality or export all \(kind)."
                let msg = lossless
                    ? "Using only the first of \(total) \(kind) is not lossless. \(losslessAdvice)"
                    : "Only the first of \(total) \(kind) will be used; the rest are discarded."
                changes.append(.init(severity: sev, message: msg, code: "frames.firstOnly"))
            case .exportAll:
                if targetPreserves {
                    describePreservation()
                } else {
                    expands = true
                    let message: String
                    let severity: ChangeSeverity
                    if source.isAnimated {
                        severity = lossless ? .blocking : .warning
                        message = lossless
                            ? "Separate frame files discard animation timing, loop count and container structure. Switch to Highest Quality to export individual frames."
                            : "All \(total) frames will be written as separate files. Animation timing, loop count and container structure are not retained."
                    } else {
                        severity = .info
                        message = "All \(total) pages will be written as separate files."
                    }
                    changes.append(.init(severity: severity,
                                         message: message,
                                         code: "frames.exportAll"))
                }
            }
        }

        // --- Alpha ---------------------------------------------------------------
        if source.hasAlpha && !target.supportsAlpha {
            if lossless {
                changes.append(.init(severity: .blocking,
                                     message: "\(target.displayName) does not support transparency.",
                                     code: "alpha.unsupported"))
            } else {
                changes.append(.init(severity: .warning,
                                     message: "Transparency will be removed and composited over the chosen background.",
                                     code: "alpha.flattened"))
            }
        }

        // --- Bit depth -----------------------------------------------------------
        let targetMaxDepth = target.bitDepths.max() ?? 8
        if source.bitsPerComponent > targetMaxDepth {
            let msg = "This output reduces the image from \(source.bitsPerComponent)-bit to \(targetMaxDepth)-bit per channel."
            changes.append(.init(severity: lossless ? .blocking : .warning, message: msg, code: "depth.reduced"))
        }

        // --- Color profile -------------------------------------------------------
        if source.hasColorProfile && !target.supportsColorProfile {
            let msg = "\(target.displayName) cannot store the color profile; the image will be interpreted as sRGB."
            changes.append(.init(severity: lossless ? .blocking : .warning, message: msg, code: "color.profileDropped"))
        }

        // --- Palette-limited targets --------------------------------------------
        if isPaletteLimited(target.id) && lossless {
            changes.append(.init(severity: .warning,
                                 message: "\(target.displayName) is limited to 256 colors; lossless is verified after encoding.",
                                 code: "palette.maybeLossy"))
        }

        // --- Lossless feasibility ------------------------------------------------
        if lossless && !target.hasLosslessPath && !isStructural {
            changes.append(.init(severity: .blocking,
                                 message: "Lossless conversion is not available for \(target.displayName).",
                                 code: "lossless.unavailable"))
        }

        // --- Metadata ------------------------------------------------------------
        switch settings.metadataPolicy {
        case .remove:
            changes.append(.init(severity: .info, message: "Metadata will be removed (color profile is kept).", code: "meta.remove"))
        case .removeLocation:
            let retained = target.supportsMetadata ? "; other metadata is kept." : "."
            if source.hasGPS {
                changes.append(.init(severity: .info, message: "GPS location will be removed\(retained)", code: "meta.removeGPS"))
            } else {
                changes.append(.init(severity: .info, message: "No GPS location found\(retained)", code: "meta.noGPS"))
            }
            if !target.supportsMetadata && (source.hasEXIF || source.hasGPS || source.hasIPTC || source.hasXMP) {
                changes.append(.init(severity: .warning, message: "\(target.displayName) can store only limited metadata.", code: "meta.limited"))
            }
        case .keep:
            if !target.supportsMetadata {
                changes.append(.init(severity: .warning, message: "\(target.displayName) can store only limited metadata.", code: "meta.limited"))
            } else if source.hasEXIF || source.hasGPS || source.hasIPTC {
                var kinds: [String] = []
                if source.hasEXIF { kinds.append("EXIF") }
                if source.hasGPS { kinds.append("GPS") }
                if source.hasIPTC { kinds.append("IPTC") }
                changes.append(.init(severity: .info, message: "Metadata (\(kinds.joined(separator: ", "))) will be preserved.", code: "meta.keep"))
            }
        }

        // --- Orientation ---------------------------------------------------------
        if let o = source.exifOrientation, o > 1 {
            if ["qoi", "pcx", "pfm", "dds", "avif"].contains(target.id) {
                changes.append(.init(severity: lossless ? .blocking : .warning,
                                     message: "\(target.displayName) output will lose the source's display orientation.",
                                     code: "orientation.unsupported"))
            } else {
                changes.append(.init(severity: .info, message: "Display orientation will be preserved.",
                                     code: "orientation.preserved"))
            }
        }

        return build(source, target, settings, changes, isStructural: isStructural, expands: expands)
    }

    // MARK: - Helpers

    private func build(_ source: ImageInfo, _ target: FormatCapability, _ settings: ConversionSettings,
                       _ changes: [FeatureChange], isStructural: Bool, expands: Bool) -> ConversionPlan {
        let worst = changes.map(\.severity).max() ?? .info
        let status: PlanStatus
        switch worst {
        case .blocking: status = .blocked
        case .warning: status = .warning
        case .info: status = .ready
        }
        return ConversionPlan(
            source: source,
            targetUTI: target.uti,
            targetDisplayName: target.displayName,
            codecId: target.id,
            settings: settings,
            status: status,
            changes: changes,
            expandsFramesOrPages: expands,
            isStructural: isStructural
        )
    }

    private func isPaletteLimited(_ id: String) -> Bool { id == "gif" }

    /// Estimated decoded size in bytes, computed with Double to avoid overflow.
    private func decodedBytes(_ info: ImageInfo) -> Double {
        if let inspected = info.decodedByteCount {
            return inspected.isFinite && inspected > 0 ? inspected : .infinity
        }
        let frames = Double(max(max(info.frameCount, info.pageCount), 1))
        let bytesPerPixel = ceil(Double(max(info.bitsPerPixel, 8)) / 8)
        return Double(info.pixelWidth) * Double(info.pixelHeight) * bytesPerPixel * frames
    }

    private func timingIsRepresentable(_ source: ImageInfo, target: FormatCapability) -> Bool {
        guard source.frameDurations.count == source.frameCount,
              let loop = source.loopCount, (0...65_535).contains(loop) else { return false }
        let ticksPerSecond: Double
        let maximumTicks: Double
        switch target.id {
        case "gif": ticksPerSecond = 100; maximumTicks = 65_535
        case "webp": ticksPerSecond = 1_000; maximumTicks = 16_777_215
        default: return false
        }
        var totalTicks = 0.0
        for duration in source.frameDurations {
            let ticks = duration * ticksPerSecond
            guard duration.isFinite, duration > 0, ticks >= 1, ticks <= maximumTicks,
                  ticks.rounded() / ticksPerSecond == duration else { return false }
            totalTicks += ticks.rounded()
        }
        return target.id != "webp" || totalTicks <= Double(Int32.max)
    }

    private func isComplexByUTI(_ uti: String?) -> Bool {
        guard let uti else { return false }
        return UTTypeBridge.conformance(uti, toIdentifier: "public.camera-raw-image")
    }
}
