import SwiftUI

@main
struct Conv3rtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Diagnostics.handleIfRequested()
    }

    private var model: AppModel { delegate.model }

    var body: some Scene {
        WindowGroup("conv3rt") {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleService([url])
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Add Files…") { addFiles(nil) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Add Folder…") { addFiles(nil) }
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste Image") { model.pasteFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsPlaceholder()
        }
    }

    private func addFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }
}

private struct SettingsPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("conv3rt").font(.title2)
            Text("Quality, metadata and output settings live in the main window's Advanced panel.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 400)
    }
}
