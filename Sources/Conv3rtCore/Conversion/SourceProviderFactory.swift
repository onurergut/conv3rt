import Foundation
import ImageIO

/// Chooses the decoder for a source: Image I/O by default, but PDF and SVG need
/// PDFKit and AppKit respectively because Image I/O does not decode them.
public enum SourceProviderFactory {

    /// Content sniffing is preferred over the extension.
    public static func detectKind(url: URL) -> Kind {
        if let head = headBytes(url, count: 512) {
            let s = String(decoding: head, as: UTF8.self)
            if s.hasPrefix("%PDF") { return .pdf }
            let trimmed = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            if trimmed.hasPrefix("<svg") || (trimmed.hasPrefix("<?xml") && s.contains("<svg")) || s.contains("<svg") {
                return .svg
            }
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ext == "svg" { return .svg }
        return .imageIO
    }

    public enum Kind { case imageIO, pdf, svg }

    public static func make(url: URL) -> (any SourceFrameProvider)? {
        switch detectKind(url: url) {
        case .pdf: return PDFFrameProvider(url: url)
        case .svg: return SVGFrameProvider(url: url)
        case .imageIO: return ImageIOFrameProvider(url: url)
        }
    }

    /// The UTI conv3rt treats a source as, for a kind that Image I/O cannot type.
    public static func uti(for kind: Kind) -> String? {
        switch kind {
        case .pdf: return "com.adobe.pdf"
        case .svg: return "public.svg-image"
        case .imageIO: return nil
        }
    }

    private static func headBytes(_ url: URL, count: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count) else { return nil }
        return Array(data)
    }
}
