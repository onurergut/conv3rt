import SwiftUI
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
                Picker("Background", selection: Binding(
                    get: { model.alphaBackground == .black ? "black" : "white" },
                    set: { model.alphaBackground = ($0 == "black") ? .black : .white }
                )) {
                    Text("White").tag("white")
                    Text("Black").tag("black")
                }
                .pickerStyle(.segmented)
                Text("Used only when a lossy target cannot store transparency, in Highest Quality mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Encoding") {
                HStack {
                    Text("Quality")
                    Slider(value: $model.lossyQuality, in: 0.5...1.0, step: 0.01)
                    Text("\(Int(model.lossyQuality * 100))%").monospacedDigit().frame(width: 44)
                }
                Text("Applies to lossy targets (JPEG, HEIC, …) in Highest Quality mode. It is not a lossless guarantee.")
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
}
