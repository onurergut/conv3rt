import SwiftUI
import AppKit
import Conv3rtCore

struct AdvancedSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Metadata") {
                Picker("Policy", selection: $model.metadataPolicy) {
                    ForEach(MetadataPolicy.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.inline)
                Text("Keep Metadata preserves EXIF, GPS, IPTC and XMP where the format allows.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Animation & Pages") {
                Picker("Policy", selection: $model.framePolicy) {
                    Text("Ask when needed").tag(FramePolicy.undecided)
                    Text("Export all frames / pages").tag(FramePolicy.exportAll)
                    Text("Use first frame / page").tag(FramePolicy.firstOnly)
                }
                .pickerStyle(.inline)
            }

            Section("Transparency") {
                Picker("Background", selection: backgroundModeBinding) {
                    Text("White").tag("white")
                    Text("Black").tag("black")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                if backgroundMode == "custom" {
                    ColorPicker("Color", selection: backgroundColorBinding, supportsOpacity: false)
                }
                Text("Used only when a lossy target cannot store transparency, in Highest Quality mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Rendering") {
                HStack {
                    Text("PDF resolution")
                    Spacer()
                    TextField("DPI", value: $model.pdfDPI, format: .number)
                        .frame(width: 64).multilineTextAlignment(.trailing)
                    Text("DPI").foregroundStyle(.secondary)
                }
                HStack {
                    Text("SVG scale")
                    Slider(value: $model.svgScale, in: 1...4, step: 0.5)
                    Text("\(model.svgScale, specifier: "%.1f")×").monospacedDigit().frame(width: 40)
                }
                Text("PDF pages and SVG are rasterized at this resolution. It is conv3rt's default, not a fixed rule.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Output") {
                Toggle("Keep source folder names", isOn: $model.keepFolderStructure)
                Text("Mirror the source's folder name under the output folder.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Quality")
                    Slider(value: $model.lossyQuality, in: 0.5...1.0, step: 0.01)
                    Text("\(Int(model.lossyQuality * 100))%").monospacedDigit().frame(width: 44)
                }
                Text("Applies to lossy targets (JPEG, HEIC, …) in Highest Quality mode. Not a lossless guarantee.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let fmt = model.selectedFormat, !fmt.limitations.isEmpty {
                Section("Known limits of \(fmt.displayName)") {
                    ForEach(fmt.limitations, id: \.self) { line in
                        Text("• \(line)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Background bindings

    private var backgroundMode: String {
        switch model.alphaBackground {
        case .white: return "white"
        case .black: return "black"
        case .custom: return "custom"
        }
    }

    private var backgroundModeBinding: Binding<String> {
        Binding(get: { backgroundMode }, set: { new in
            switch new {
            case "black": model.alphaBackground = .black
            case "custom": model.alphaBackground = .custom(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            default: model.alphaBackground = .white
            }
        })
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(get: {
            switch model.alphaBackground {
            case .custom(let r, let g, let b, _): return Color(red: r, green: g, blue: b)
            case .black: return .black
            case .white: return .white
            }
        }, set: { newColor in
            let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .white
            model.alphaBackground = .custom(red: Double(ns.redComponent),
                                            green: Double(ns.greenComponent),
                                            blue: Double(ns.blueComponent), alpha: 1)
        })
    }
}
