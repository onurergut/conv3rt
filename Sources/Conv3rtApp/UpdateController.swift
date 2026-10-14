import Foundation
import Combine
import Sparkle

struct UpdateConfiguration {
    let feedURL: URL
    let publicKey: String

    init?(bundleURL: URL, feed: String, publicKey: String) {
        guard bundleURL.pathExtension == "app", let url = URL(string: feed),
              url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil,
              Data(base64Encoded: publicKey)?.count == 32 else { return nil }
        self.feedURL = url
        self.publicKey = publicKey
    }

    init?(bundle: Bundle) {
        guard bundle.bundleIdentifier == "com.conv3rt.app",
              let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              ["SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate", "SUEnableSystemProfiling", "SUSendProfileInfo"].allSatisfy({
                  bundle.object(forInfoDictionaryKey: $0) as? Bool == false
              }) else { return nil }
        self.init(bundleURL: bundle.bundleURL, feed: feed, publicKey: key)
    }
}

@MainActor
protocol UpdateDriver: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sendsSystemProfile: Bool { get set }
    var onChange: (() -> Void)? { get set }
    func start() throws
    func checkForUpdates()
}

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isAvailable = false
    @Published private(set) var lastError: String?
    @Published private var revision = 0
    private let gate: UpdateSafetyGate
    private let configuration: UpdateConfiguration?
    private let factory: @MainActor (UpdateController) -> any UpdateDriver
    private var driver: (any UpdateDriver)?
    private var gateChanges: AnyCancellable?
    private var startRequested = false
    private var started = false

    init(gate: UpdateSafetyGate, configuration: UpdateConfiguration? = UpdateConfiguration(bundle: .main),
         factory: @escaping @MainActor (UpdateController) -> any UpdateDriver = { SparkleUpdateDriver(delegate: $0) }) {
        self.gate = gate
        self.configuration = configuration
        self.factory = factory
        super.init()
        gateChanges = gate.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                revision += 1
                startIfIdle()
            }
        }
    }

    var canCheckForUpdates: Bool {
        _ = revision
        return started && !gate.isBusy && !gate.blocksNewWork && driver?.canCheckForUpdates == true
    }

    var automaticallyChecksForUpdates: Bool {
        get { _ = revision; return driver?.automaticallyChecksForUpdates ?? false }
        set {
            guard started else { return }
            driver?.automaticallyChecksForUpdates = newValue
            revision += 1
        }
    }

    func start() {
        startRequested = true
        startIfIdle()
    }

    private func startIfIdle() {
        guard startRequested, !started, configuration != nil, !gate.isBusy, !gate.blocksNewWork else { return }
        let driver = factory(self)
        driver.automaticallyDownloadsUpdates = false
        driver.sendsSystemProfile = false
        driver.onChange = { [weak self] in self?.revision += 1 }
        do {
            try driver.start()
            self.driver = driver
            started = true
            isAvailable = true
        } catch {
            startRequested = false
            lastError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        driver?.checkForUpdates()
    }

    func postponeInstallation(_ handler: @escaping () -> Void) -> Bool {
        gate.requestInstallation(handler)
        return true
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !gate.isBusy, !gate.blocksNewWork else {
            throw NSError(domain: "com.conv3rt.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Finish importing or converting before checking for updates."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation(installHandler)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        gate.abortInstallation()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        gate.cancelInstallation()
    }
}

@MainActor
private final class SparkleUpdateDriver: UpdateDriver {
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []
    var onChange: (() -> Void)?

    init(delegate: any SPUUpdaterDelegate) {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        observations = [
            controller.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.onChange?() } },
            controller.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.onChange?() } }
        ]
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    var sendsSystemProfile: Bool {
        get { controller.updater.sendsSystemProfile }
        set { controller.updater.sendsSystemProfile = newValue }
    }
    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}
