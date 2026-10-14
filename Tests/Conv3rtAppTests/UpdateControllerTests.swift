import XCTest
import Combine
import Sparkle
@testable import Conv3rtApp

final class UpdateControllerTests: XCTestCase {
    @MainActor
    func testUnconfiguredBuildDoesNotConstructUpdater() {
        var creations = 0
        let updates = UpdateController(gate: UpdateSafetyGate(), configuration: nil) { _ in
            creations += 1
            return TestDriver()
        }
        updates.start()
        updates.checkForUpdates()
        XCTAssertEqual(creations, 0)
        XCTAssertFalse(updates.isAvailable)
        XCTAssertFalse(updates.canCheckForUpdates)
    }

    func testConfigurationRequiresPackagedHostHTTPSAndPublicKey() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertNil(UpdateConfiguration(bundleURL: URL(fileURLWithPath: "/tmp/conv3rt"),
                                        feed: "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-arm64.xml", publicKey: key))
        for feed in ["http://example.com/feed", "file:///tmp/feed", "https://user:password@example.com/feed"] {
            XCTAssertNil(UpdateConfiguration(bundleURL: URL(fileURLWithPath: "/tmp/conv3rt.app"), feed: feed, publicKey: key))
        }
        XCTAssertNil(UpdateConfiguration(bundleURL: URL(fileURLWithPath: "/tmp/conv3rt.app"),
                                        feed: "https://example.com/feed", publicKey: "invalid"))
    }

    @MainActor
    func testSparkleDelegateSelectorsAreConnected() {
        let updates = UpdateController(gate: UpdateSafetyGate(), configuration: nil)
        for name in ["updater:mayPerformUpdateCheck:error:",
                     "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
                     "updater:didAbortWithError:",
                     "updater:didFinishUpdateCycleForUpdateCheck:error:"] {
            XCTAssertTrue(updates.responds(to: NSSelectorFromString(name)), name)
        }
    }

    @MainActor
    func testStartsOnceWithoutEnablingAutomaticChecks() {
        let driver = TestDriver()
        let updates = UpdateController(gate: UpdateSafetyGate(), configuration: configuration()) { _ in driver }
        updates.start()
        updates.start()
        XCTAssertEqual(driver.starts, 1)
        XCTAssertFalse(updates.automaticallyChecksForUpdates)
        XCTAssertFalse(driver.automaticallyDownloadsUpdates)
        XCTAssertFalse(driver.sendsSystemProfile)
    }

    @MainActor
    func testStartupWaitsUntilAdmittedWorkIsFinished() async throws {
        let gate = UpdateSafetyGate()
        let driver = TestDriver()
        let work = try XCTUnwrap(gate.beginWork())
        let updates = UpdateController(gate: gate, configuration: configuration()) { _ in driver }
        updates.start()
        XCTAssertEqual(driver.starts, 0)
        let started = expectation(description: "Updater starts only after idle")
        let subscription = updates.$isAvailable.dropFirst().filter { $0 }.sink { _ in started.fulfill() }
        gate.endWork(work)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(driver.starts, 1)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testBusyWorkBlocksSparkleDelegateCheck() throws {
        let gate = UpdateSafetyGate()
        let updates = UpdateController(gate: gate, configuration: nil)
        let controller = Sparkle.SPUStandardUpdaterController(startingUpdater: false,
                                                              updaterDelegate: nil, userDriverDelegate: nil)
        let work = try XCTUnwrap(gate.beginWork())
        XCTAssertThrowsError(try updates.updater(controller.updater, mayPerform: .updates))
        gate.endWork(work)
        XCTAssertNoThrow(try updates.updater(controller.updater, mayPerform: .updates))
    }

    @MainActor
    func testBusyWorkBlocksManualCheck() throws {
        let gate = UpdateSafetyGate()
        let driver = TestDriver()
        let updates = UpdateController(gate: gate, configuration: configuration()) { _ in driver }
        updates.start()
        let work = try XCTUnwrap(gate.beginWork())
        XCTAssertFalse(updates.canCheckForUpdates)
        updates.checkForUpdates()
        XCTAssertEqual(driver.checks, 0)
        gate.endWork(work)
        updates.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
    }

    @MainActor
    func testConsentSettingChangesOnlyWhenUserChoosesIt() {
        let driver = TestDriver()
        let updates = UpdateController(gate: UpdateSafetyGate(), configuration: configuration()) { _ in driver }
        updates.start()
        updates.automaticallyChecksForUpdates = true
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
        updates.automaticallyChecksForUpdates = false
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        XCTAssertFalse(driver.automaticallyDownloadsUpdates)
    }

    @MainActor
    func testInstallationWaitsForBusyWorkAndBlocksNewCheck() throws {
        let gate = UpdateSafetyGate()
        let driver = TestDriver()
        let updates = UpdateController(gate: gate, configuration: configuration()) { _ in driver }
        updates.start()
        let work = try XCTUnwrap(gate.beginWork())
        var installations = 0
        XCTAssertTrue(updates.postponeInstallation { installations += 1 })
        XCTAssertFalse(updates.canCheckForUpdates)
        XCTAssertNil(gate.beginWork())
        XCTAssertEqual(installations, 0)
        gate.endWork(work)
        XCTAssertEqual(installations, 1)
    }

    @MainActor
    private func configuration() -> UpdateConfiguration {
        UpdateConfiguration(bundleURL: URL(fileURLWithPath: "/tmp/conv3rt.app"),
                            feed: "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-arm64.xml",
                            publicKey: Data(repeating: 1, count: 32).base64EncodedString())!
    }

    @MainActor
    private final class TestDriver: UpdateDriver {
        var starts = 0
        var checks = 0
        var canCheckForUpdates = true
        var automaticallyChecksForUpdates = false
        var automaticallyDownloadsUpdates = true
        var sendsSystemProfile = true
        var onChange: (() -> Void)?
        func start() throws { starts += 1 }
        func checkForUpdates() { checks += 1 }
    }
}
