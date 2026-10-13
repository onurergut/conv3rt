import Foundation

/// Hand-authored knowledge about each format: extensions, features, and caveats.
///
/// This table records *static* facts (what a format can represent). Actual
/// read/write availability is taken from the runtime probe and merged in by
/// `CapabilityRegistry`. Feature flags here are conservative and carry an
/// `Evidence` level so the UI can distinguish verified claims from documented
/// ones.
public enum FormatCatalog {

    public static let all: [FormatCapability] = [
        // MARK: - Common formats

        {
            var c = FormatCapability(id: "jpeg", uti: "public.jpeg", displayName: "JPEG",
                                     fileExtensions: ["jpg", "jpeg", "jpe", "jfif"])
            c.bitDepths = [8]
            c.supportsAlpha = false
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Lossy only.", "No transparency.", "Best kept to 8-bit."]
            c.evidence = .documented
            return c
        }(),

        {
            var c = FormatCapability(id: "png", uti: "public.png", displayName: "PNG",
                                     fileExtensions: ["png"])
            c.bitDepths = [1, 2, 4, 8, 16]
            c.supportsAlpha = true
            c.supportsAnimation = false  // APNG write path not verified; treated as not preserved.
            c.supportsMultiPage = false
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = true
            c.losslessConditions = [.alphaPreserved, .bitDepthPreserved, .colorProfilePreserved, .exactSamples]
            c.limitations = ["Animated PNG (APNG) output is not verified; animated sources must be split or reduced to the first frame.",
                             "Static PNG is fully lossless."]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "tiff", uti: "public.tiff", displayName: "TIFF",
                                     fileExtensions: ["tif", "tiff"])
            c.bitDepths = [8, 16, 32]
            c.supportsAlpha = true
            c.supportsMultiPage = true
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = true
            c.losslessConditions = [.alphaPreserved, .bitDepthPreserved, .colorProfilePreserved, .exactSamples, .multipagePreserved]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "bmp", uti: "com.microsoft.bmp", displayName: "BMP",
                                     fileExtensions: ["bmp"])
            c.bitDepths = [1, 4, 8, 24, 32]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.alphaPreserved, .bitDepthPreserved, .exactSamples]
            c.limitations = ["No color profile.", "Limited metadata."]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "gif", uti: "com.compuserve.gif", displayName: "GIF",
                                     fileExtensions: ["gif"])
            c.bitDepths = [8]
            c.supportsAlpha = true   // 1-bit transparency only.
            c.supportsAnimation = true
            c.supportsColorProfile = false
            c.supportsMetadata = true
            c.hasLosslessPath = true
            c.losslessConditions = [.paletteFits, .alphaPreserved, .animationPreserved, .exactSamples]
            c.limitations = ["Indexed palette of at most 256 colors.", "1-bit transparency only.",
                             "Lossless only when the source palette fits."]
            c.evidence = .documented
            return c
        }(),

        {
            var c = FormatCapability(id: "heic", uti: "public.heic", displayName: "HEIC / HEIF",
                                     fileExtensions: ["heic", "heif"])
            c.bitDepths = [8, 10, 12]
            c.supportsAlpha = true
            c.supportsAnimation = true   // HEICS sequences.
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Lossless label requires the full YUV pipeline to be verified; not claimed here.",
                             "Encoder may convert RGB to YUV and subsample chroma."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "webp", uti: "org.webmproject.webp", displayName: "WebP",
                                     fileExtensions: ["webp"], provider: .imageIO)
            c.bitDepths = [8]
            c.supportsAlpha = true
            c.supportsAnimation = false  // writing animated WebP is not implemented
            c.supportsColorProfile = true
            c.supportsMetadata = false
            c.hasLosslessPath = true   // via bundled libwebp exact mode.
            c.losslessConditions = [.alphaPreserved, .colorProfilePreserved, .exactSamples]
            c.limitations = ["Native macOS reads WebP but cannot write it; conv3rt writes WebP with the bundled libwebp.",
                             "Lossless mode uses libwebp exact mode to preserve RGB under fully transparent pixels.",
                             "The ICC profile is written (ICCP); EXIF/XMP are not yet written.",
                             "Animated WebP output is not implemented."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "avif", uti: "public.avif", displayName: "AVIF",
                                     fileExtensions: ["avif"])
            c.bitDepths = [8, 10, 12]
            c.supportsAlpha = true
            c.supportsAnimation = true   // AVIF sequences; read only natively.
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Native macOS can read AVIF but not write it; writing is out of scope unless a bundled encoder is added.",
                             "RGB→YUV, range, matrix, bit depth and subsampling can all lose data."]
            c.evidence = .unverified
            return c
        }(),

        {
            var c = FormatCapability(id: "jxl", uti: "public.jpeg-xl", displayName: "JPEG XL",
                                     fileExtensions: ["jxl"])
            c.bitDepths = [8, 16, 32]
            c.supportsAlpha = true
            c.supportsAnimation = false  // writing animated JXL is not implemented
            c.supportsColorProfile = true
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples, .colorProfilePreserved]
            c.limitations = ["Native macOS reads JPEG XL but cannot write it; conv3rt writes JXL with a bundled libjxl (off by default until built).",
                             "The ICC profile is embedded; EXIF/XMP are not yet written.",
                             "Animated JPEG XL output is not implemented."]
            c.evidence = .verified
            return c
        }(),

        // MARK: - Extended / professional raster

        {
            var c = FormatCapability(id: "jp2", uti: "public.jpeg-2000", displayName: "JPEG 2000",
                                     fileExtensions: ["jp2", "j2k", "jpf", "jpx"])
            c.bitDepths = [8, 16]
            c.supportsAlpha = true
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Image I/O writes JPEG 2000 lossily by default; a genuine lossless JP2 write path is not implemented."]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "exr", uti: "com.ilm.openexr-image", displayName: "OpenEXR",
                                     fileExtensions: ["exr"])
            c.bitDepths = [16, 32]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = true
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples, .notStructural]
            c.limitations = ["EXR may use lossy or lossless compression; the compression method and channel types must be checked per file.",
                             "Floating-point and half-float data are preserved; do not route through an 8-bit path."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "radiance", uti: "public.radiance", displayName: "Radiance HDR",
                                     fileExtensions: ["hdr", "pic"])
            c.bitDepths = [32]
            c.supportsAlpha = false
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["RGBE encoding; read-only natively."]
            c.evidence = .documented
            return c
        }(),

        {
            var c = FormatCapability(id: "tga", uti: "com.truevision.tga-image", displayName: "TGA",
                                     fileExtensions: ["tga"])
            c.bitDepths = [8, 16, 24, 32]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples, .alphaPreserved]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "ico", uti: "com.microsoft.ico", displayName: "ICO",
                                     fileExtensions: ["ico"])
            c.bitDepths = [8, 32]
            c.supportsAlpha = true
            c.supportsMultiPage = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples]
            c.limitations = ["Windows icon container; multiple sizes are separate images."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "icns", uti: "com.apple.icns", displayName: "ICNS",
                                     fileExtensions: ["icns"])
            c.bitDepths = [8, 32]
            c.supportsAlpha = true
            c.supportsMultiPage = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples]
            c.limitations = ["macOS icon container; multiple sizes are separate images."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "pnm", uti: "public.pbm", displayName: "Netpbm (PBM/PGM/PPM)",
                                     fileExtensions: ["pbm", "pgm", "ppm", "pnm"])
            c.bitDepths = [1, 8, 16]
            c.supportsAlpha = false
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples, .bitDepthPreserved]
            c.limitations = ["Verified lossless for RGB via the native Netpbm writer."]
            c.evidence = .tested
            return c
        }(),

        {
            var c = FormatCapability(id: "dds", uti: "com.microsoft.dds", displayName: "DDS",
                                     fileExtensions: ["dds"])
            c.bitDepths = [8]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["DirectDraw Surface; commonly block-compressed (BCn), which is lossy."]
            c.evidence = .unverified
            return c
        }(),

        {
            var c = FormatCapability(id: "sgi", uti: "com.sgi.sgi-image", displayName: "SGI",
                                     fileExtensions: ["sgi", "rgb"])
            c.bitDepths = [8, 16]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.hasLosslessPath = true
            c.losslessConditions = [.exactSamples]
            c.evidence = .unverified
            return c
        }(),

        {
            var c = FormatCapability(id: "pict", uti: "com.apple.pict", displayName: "PICT",
                                     fileExtensions: ["pict", "pct"])
            c.bitDepths = [8]
            c.supportsAlpha = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Legacy QuickDraw format; read-only."]
            c.evidence = .documented
            return c
        }(),

        // MARK: - Complex sources (raster export)

        {
            var c = FormatCapability(id: "psd", uti: "com.adobe.photoshop-image", displayName: "Photoshop (PSD)",
                                     fileExtensions: ["psd"])
            c.bitDepths = [8, 16, 32]
            c.supportsAlpha = true
            c.isComplexSource = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Exports the merged/rendered image only; editable layers are not preserved.",
                             "Photoshop variants unsupported by Image I/O produce a clear error."]
            c.evidence = .documented
            return c
        }(),

        {
            var c = FormatCapability(id: "raw", uti: "public.camera-raw-image", displayName: "Camera RAW",
                                     fileExtensions: ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
                                                      "pef", "srw", "nrw", "rwl", "srf", "sr2", "erf", "fff",
                                                      "iiq", "3fr", "mrw", "dcr", "mos", "kdc", "rwz"])
            c.bitDepths = [8, 16]
            c.supportsAlpha = false
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.isComplexSource = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Demosaiced to a rendered image; the raw sensor data is not preserved and no camera RAW can be produced as output.",
                             "Camera/variant support depends on the OS; DNG is the most portable family."]
            c.evidence = .unverified
            return c
        }(),

        {
            var c = FormatCapability(id: "svg", uti: "public.svg-image", displayName: "SVG (vector)",
                                     fileExtensions: ["svg"], provider: .bundled)
            c.bitDepths = [8]
            c.supportsAlpha = true
            c.supportsColorProfile = false
            c.supportsMetadata = false
            c.isComplexSource = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Rasterized to pixels by AppKit; not true vector-to-raster lossless.",
                             "Scripts are not executed and remote resources are not downloaded.",
                             "External fonts and linked images may be unavailable."]
            c.evidence = .verified
            return c
        }(),

        {
            var c = FormatCapability(id: "pdf", uti: "com.adobe.pdf", displayName: "PDF",
                                     fileExtensions: ["pdf"], provider: .pdfKit)
            c.bitDepths = [8]
            c.supportsAlpha = true
            c.supportsMultiPage = true
            c.supportsColorProfile = true
            c.supportsMetadata = true
            c.isComplexSource = true
            c.hasLosslessPath = false
            c.losslessConditions = [.notStructural]
            c.limitations = ["Pages are rendered to a raster image at a chosen resolution; the vector PDF structure is not preserved.",
                             "Encrypted PDFs produce a clear error."]
            c.evidence = .unverified
            return c
        }(),
    ]

    /// Catalog entries indexed by UTI.
    public static let byUTI: [String: FormatCapability] = {
        var map: [String: FormatCapability] = [:]
        for c in all { map[c.uti] = c }
        return map
    }()
}
