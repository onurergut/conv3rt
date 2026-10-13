import Foundation
import Conv3rtCore

/// A named bundle of the app's conversion settings.
///
/// `AlphaBackground` is not `Codable`, so it is stored via its round-trippable
/// `storageString`.
struct ConversionPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var formatID: String
    var mode: ConversionMode
    var metadataPolicy: MetadataPolicy
    var framePolicy: FramePolicy
    var alphaBackgroundStorage: String
    var lossyQuality: Double
    var pdfDPI: Double
    var svgScale: Double
    var keepFolderStructure: Bool

    init(
        id: UUID = UUID(),
        name: String,
        formatID: String,
        mode: ConversionMode,
        metadataPolicy: MetadataPolicy,
        framePolicy: FramePolicy,
        alphaBackground: AlphaBackground,
        lossyQuality: Double,
        pdfDPI: Double,
        svgScale: Double,
        keepFolderStructure: Bool
    ) {
        self.id = id
        self.name = name
        self.formatID = formatID
        self.mode = mode
        self.metadataPolicy = metadataPolicy
        self.framePolicy = framePolicy
        self.alphaBackgroundStorage = alphaBackground.storageString
        self.lossyQuality = lossyQuality
        self.pdfDPI = pdfDPI
        self.svgScale = svgScale
        self.keepFolderStructure = keepFolderStructure
    }

    var alphaBackground: AlphaBackground { AlphaBackground.fromStorage(alphaBackgroundStorage) }
}

/// Loads and saves named conversion presets in `UserDefaults`.
struct PresetStore {
    private let defaults: UserDefaults
    private let key = "conv3rt.presets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ConversionPreset] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ConversionPreset].self, from: data)) ?? []
    }

    func save(_ presets: [ConversionPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
