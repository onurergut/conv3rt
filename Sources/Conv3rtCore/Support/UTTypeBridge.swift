import Foundation
import UniformTypeIdentifiers

/// Thin wrapper over Uniform Type Identifiers so the rest of the core does not
/// import UniformTypeIdentifiers everywhere, and so identifiers can be
/// converted to display names / extensions consistently.
public enum UTTypeBridge {

    public static func preferredFilenameExtension(_ identifier: String) -> String? {
        UTType(identifier)?.preferredFilenameExtension
    }

    public static func localizedDescription(_ identifier: String) -> String? {
        UTType(identifier)?.localizedDescription
    }

    public static func identifier(forExtension ext: String) -> String? {
        UTType(filenameExtension: ext)?.identifier
    }

    public static func conformance(_ identifier: String, to parent: UTType) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: parent)
    }

    public static func conformance(_ identifier: String, toIdentifier parent: String) -> Bool {
        guard let type = UTType(identifier), let parentType = UTType(parent) else { return false }
        return type.conforms(to: parentType)
    }

    /// True when the identifier conforms to `public.image`.
    public static func isImage(_ identifier: String) -> Bool {
        conformance(identifier, to: .image)
    }
}
