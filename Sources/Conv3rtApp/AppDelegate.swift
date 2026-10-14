import AppKit
import Foundation

/// Handles macOS Services (Finder "Quick Actions"). A Finder right-click on
/// selected images shows "Convert with conv3rt", which starts a conversion
/// using the app's current settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let model = AppModel()
    lazy var updates = UpdateController(gate: model.updateGate)
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = ServicesProvider(model: model)
        servicesProvider = provider
        NSApp.servicesProvider = provider
        // Refresh the Services registry so the menu item appears without a
        // log out/in the first time the app runs.
        NSUpdateDynamicServices()
        updates.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.updateGate.blocksNewWork && model.updateGate.isBusy { return .terminateCancel }
        return .terminateNow
    }

    /// Return paths for files dragged onto the app icon in the Dock.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        model.handleService(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }
}

/// The object the Services system calls. `convertWithConv3rt:` matches the
/// `NSMessage` in Info.plist.
@MainActor
final class ServicesProvider: NSObject {

    private let model: AppModel
    init(model: AppModel) { self.model = model }

    @objc(convertWithConv3rt:userData:error:)
    func convertWithConv3rt(_ pboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Select one or more image files." as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        model.handleService(urls)
    }
}
