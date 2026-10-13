import Foundation
import ImageIO

/// Chooses the decoder for a source: Image I/O by default, PDFKit/AppKit for
/// PDF and SVG, and the bundled codecs for QOI/PCX/PFM which Image I/O cannot
/// read.
public enum SourceProviderFactory {

    public enum Kind { case imageIO, pdf, svg, qoi, pcx, pfm }

    public static func detectKind(url: URL) -> Kind {
        if let head = headBytes(url, count: 512) {
            if QOICodec.canDecode(Data(head)) { return .qoi }
            if PCXCodec.canDecode(Data(head)) { return .pcx }
            let s = String(decoding: head, as: UTF8.self)
            if s.hasPrefix("PF") || s.hasPrefix("Pf") { return .pfm }
            if s.hasPrefix("%PDF") { return .pdf }
            let trimmed = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            if trimmed.hasPrefix("<svg") || (trimmed.hasPrefix("<?xml") && s.contains("<svg")) || s.contains("<svg") {
                return .svg
            }
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "svg": return .svg
        case "qoi": return .qoi
        case "pcx": return .pcx
        case "pfm": return .pfm
        default: return .imageIO
        }
    }

    public static func make(url: URL, dpi: Double = 144, svgScale: Double = 2.0)
        -> (any SourceFrameProvider)? {
        switch detectKind(url: url) {
        case .pdf: return PDFFrameProvider(url: url, dpi: CGFloat(dpi))
        case .svg: return SVGFrameProvider(url: url, scale: CGFloat(svgScale))
        case .qoi: return decodeStatic(url: url, decode: QOICodec.decode)
        case .pcx: return decodeStatic(url: url, decode: PCXCodec.decode)
        case .pfm: return decodeStatic(url: url, decode: NetpbmCodec.decode)
        case .imageIO: return ImageIOFrameProvider(url: url)
        }
    }

    /// The UTI conv3rt treats a source as, for a kind Image I/O cannot type.
    public static func uti(for kind: Kind) -> String? {
        switch kind {
        case .pdf: return "com.adobe.pdf"
        case .svg: return "public.svg-image"
        case .qoi: return "com.conv3rt.qoi"
        case .pcx: return "com.conv3rt.pcx"
        case .pfm: return "com.conv3rt.pfm"
        case .imageIO: return nil
        }
    }

    private static func decodeStatic(url: URL, decode: (Data) throws -> CGImage)
        -> (any SourceFrameProvider)? {
        guard let data = try? Data(contentsOf: url), let image = try? decode(data) else { return nil }
        return StaticImageProvider(image: image)
    }

    private static func headBytes(_ url: URL, count: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count) else { return nil }
        return Array(data)
    }
}
