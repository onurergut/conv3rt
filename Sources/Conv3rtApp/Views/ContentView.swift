import SwiftUI
import UniformTypeIdentifiers
import Conv3rtCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdvanced = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if model.items.isEmpty {
                dropPrompt
            } else {
                fileList
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 520)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    presentOpenPanel(folders: false)
                } label: { Label("Add Files", systemImage: "plus") }
                    .help("Add image files")

                Button {
                    presentOpenPanel(folders: true)
                } label: { Label("Add Folder", systemImage: "folder") }
                    .help("Add every image in a folder")

                Button {
                    model.pasteFromClipboard()
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .help("Paste an image from the clipboard")
            }
            ToolbarItem { Spacer() }
            ToolbarItem {
                Toggle(isOn: $showAdvanced) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .help("Show advanced settings")
            }
        }
        .inspector(isPresented: $showAdvanced) {
            AdvancedSettingsView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .alert("conv3rt", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Output Format").font(.caption).foregroundStyle(.secondary)
                Picker("Output Format", selection: $model.selectedFormatID) {
                    ForEach(model.writableFormats) { fmt in
                        Text(fmt.displayName).tag(fmt.id)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 160)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Quality").font(.caption).foregroundStyle(.secondary)
                Picker("Quality", selection: $model.mode) {
                    ForEach(ConversionMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .help(model.mode.subtitle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Output Folder").font(.caption).foregroundStyle(.secondary)
                Button {
                    model.chooseOutputFolder()
                } label: {
                    Label(model.outputDirectory?.lastPathComponent ?? "Choose…",
                          systemImage: "folder.badge.gearshape")
                        .lineLimit(1)
                }
                .help(model.outputDirectory?.path ?? "Choose an output folder")
            }

            if model.isRunning {
                Button(role: .cancel) { model.cancel() } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    model.startConversion()
                } label: {
                    Label("Convert", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.convertibleCount == 0 || model.outputDirectory == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    // MARK: - Drop prompt

    private var dropPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drag images here").font(.title3)
            Text("Or use Add Files, Add Folder, or paste from the clipboard.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - File list

    private var fileList: some View {
        Table(model.items) {
            TableColumn("") { item in
                Group {
                    if let img = item.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .width(48)

            TableColumn("Name") { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName).lineLimit(1)
                    if let info = item.info {
                        Text(info.detectedUTI.map { shortName($0) } ?? "—")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            TableColumn("Dimensions") { item in
                Text(item.info?.pixelDescription ?? "—").monospacedDigit()
            }
            .width(110)

            TableColumn("Size") { item in
                Text(byteString(item.info?.fileSize ?? 0)).monospacedDigit()
            }
            .width(80)

            TableColumn("Frames") { item in
                let n = max(item.info?.frameCount ?? 1, item.info?.pageCount ?? 1)
                Text(n > 1 ? "\(n)" : "—").monospacedDigit()
            }
            .width(60)

            TableColumn("Status") { item in
                statusCell(item)
            }
        }
    }

    @ViewBuilder
    private func statusCell(_ item: ImportItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if item.plan?.status == .blocked {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                } else if item.plan?.status == .warning {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if case .succeeded = item.state {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if case .failed = item.state {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Text(item.statusText).lineLimit(1)
            }
            if let plan = item.plan, let first = plan.blockingChanges.first ?? plan.warnings.first {
                Text(first.message).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contextMenu {
            if !item.resultURLs.isEmpty {
                Button("Reveal in Finder") { model.reveal(item.resultURLs) }
            }
            Button("Remove", role: .destructive) { model.remove(item) }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.isRunning { ProgressView(value: model.progress).frame(maxWidth: 220) }
            Text(model.statusLine).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.outputDirectory != nil {
                Button {
                    model.openOutputFolder()
                } label: { Label("Open Output Folder", systemImage: "folder") }
                    .disabled(model.isRunning)
            }
            if model.items.contains(where: { if case .failed = $0.state { return true }; return false }) {
                Button("Retry Failed") { model.retryFailed() }.disabled(model.isRunning)
            }
            if !model.items.isEmpty {
                Button("Clear") { model.clearAll() }.disabled(model.isRunning)
            }
        }
        .padding(10)
    }

    // MARK: - Helpers

    private func presentOpenPanel(folders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            model.addFiles(urls)
        }
        return true
    }

    private func shortName(_ uti: String) -> String {
        UTTypeBridge.localizedDescription(uti) ?? uti
    }

    private func byteString(_ size: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: size)
    }
}
