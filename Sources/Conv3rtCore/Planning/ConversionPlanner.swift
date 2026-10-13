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
        if total > 1 {
            switch settings.framePolicy {
            case .undecided:
                if !targetPreserves {
                    changes.append(.init(severity: .blocking,
                                         message: "\(target.displayName) cannot store all \(total) \(kind). Choose to export all \(kind) or use the first one.",
                                         code: "frames.decisionRequired"))
                } else {
                    changes.append(.init(severity: .info,
                                         message: "All \(total) \(kind) and their timing will be preserved.",
                                         code: "frames.preserved"))
                }
            case .firstOnly:
                // Discarding frames/pages is a content loss independent of
                // whether the target could have held them, so it can never be
                // offered as Lossless.
                let sev: ChangeSeverity = lossless ? .blocking : .warning
                let msg = lossless
                    ? "Using only the first of \(total) \(kind) is not lossless. Switch to Highest Quality or export all \(kind)."
                    : "Only the first of \(total) \(kind) will be used; the rest are discarded."
                changes.append(.init(severity: sev, message: msg, code: "frames.firstOnly"))
            case .exportAll:
                if targetPreserves {
                    changes.append(.init(severity: .info,
                                         message: "All \(total) \(kind) and their timing will be preserved.",
                                         code: "frames.preserved"))
                } else {
                    expands = true
                    changes.append(.init(severity: .info,
                                         message: "All \(total) \(kind) will be written as separate files.",
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
            if source.hasGPS {
                changes.append(.init(severity: .info, message: "GPS location will be removed; other metadata is kept.", code: "meta.removeGPS"))
            } else {
                changes.append(.init(severity: .info, message: "No GPS location found; other metadata is kept.", code: "meta.noGPS"))
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
            changes.append(.init(severity: .info, message: "EXIF orientation (\(o)) is applied so the image displays correctly.", code: "orientation.applied"))
        }

        return build(source, target, settings, changes, isStructural: isStructural, expands: expands)
    }

    /// Convenience: returns a plan, or the specific planning error.
    public func planOrThrow(source: ImageInfo, target: FormatCapability,
                            settings: ConversionSettings) -> ConversionPlan {
        plan(source: source, target: target, settings: settings)
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
        let frames = Double(max(max(info.frameCount, info.pageCount), 1))
        let bytesPerPixel = Double(max(info.bitsPerPixel, 8) / 8)
        return Double(info.pixelWidth) * Double(info.pixelHeight) * bytesPerPixel * frames
    }

    private func isComplexByUTI(_ uti: String?) -> Bool {
        guard let uti else { return false }
        return UTTypeBridge.conformance(uti, toIdentifier: "public.camera-raw-image")
    }
}
