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
            CommandGroup(after: .appInfo) {
                UpdateCommands(updates: delegate.updates)
            }
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
            SettingsPlaceholder(updates: delegate.updates)
        }
    }

    private func addFiles(_ sender: Any?) {
        guard let work = model.updateGate.beginWork() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.addAdmittedFiles(panel.urls, work: work)
        } else {
            model.updateGate.endWork(work)
        }
    }
}

private struct UpdateCommands: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates)
    }
}

private struct SettingsPlaceholder: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        VStack(spacing: 8) {
            Text("conv3rt").font(.title2)
            Text("Quality, metadata and output settings live in the main window's Advanced panel.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 8)
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: { updates.automaticallyChecksForUpdates = $0 }
            ))
            .disabled(!updates.isAvailable)
            Button("Check for Updates…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            if let error = updates.lastError { Text(error).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(24)
        .frame(width: 400)
    }
}
