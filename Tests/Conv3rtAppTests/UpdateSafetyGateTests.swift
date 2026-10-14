import XCTest
@testable import Conv3rtApp

final class UpdateSafetyGateTests: XCTestCase {
    @MainActor
    func testInstallationWaitsForAllAdmittedWork() throws {
        let gate = UpdateSafetyGate()
        let first = try XCTUnwrap(gate.beginWork())
        let second = try XCTUnwrap(gate.beginWork())
        var installs = 0
        gate.requestInstallation { installs += 1 }
        XCTAssertTrue(gate.blocksNewWork)
        XCTAssertNil(gate.beginWork())
        gate.endWork(first)
        XCTAssertEqual(installs, 0)
        gate.endWork(second)
        XCTAssertEqual(installs, 1)
        gate.endWork(second)
        XCTAssertEqual(installs, 1)
        XCTAssertTrue(gate.blocksNewWork)
    }

    @MainActor
    func testAdmittedServiceCanFinishImportToConversionHandoff() throws {
        let gate = UpdateSafetyGate()
        let service = try XCTUnwrap(gate.beginWork())
        gate.requestInstallation {}
        let conversion = try XCTUnwrap(gate.beginWork(admitted: true))
        gate.endWork(service)
        XCTAssertTrue(gate.isBusy)
        gate.endWork(conversion)
        XCTAssertFalse(gate.isBusy)
        XCTAssertTrue(gate.installationStarted)
    }

    @MainActor
    func testCanceledInstallationDiscardsHandlerAndUnlocks() throws {
        let gate = UpdateSafetyGate()
        let token = try XCTUnwrap(gate.beginWork())
        var installs = 0
        gate.requestInstallation { installs += 1 }
        gate.cancelInstallation()
        gate.endWork(token)
        XCTAssertEqual(installs, 0)
        XCTAssertFalse(gate.blocksNewWork)
        XCTAssertNotNil(gate.beginWork())
    }

    @MainActor
    func testDuplicateInstallRequestCannotReplacePendingHandler() throws {
        let gate = UpdateSafetyGate()
        let token = try XCTUnwrap(gate.beginWork())
        var installs = 0
        gate.requestInstallation { installs += 1 }
        gate.requestInstallation { installs += 10 }
        gate.endWork(token)
        XCTAssertEqual(installs, 1)
    }

    @MainActor
    func testAbortedInstallationAllowsWorkAgain() {
        let gate = UpdateSafetyGate()
        gate.requestInstallation {}
        XCTAssertTrue(gate.installationStarted)
        gate.abortInstallation()
        XCTAssertFalse(gate.installationStarted)
        XCTAssertFalse(gate.blocksNewWork)
        XCTAssertNotNil(gate.beginWork())
    }

    @MainActor
    func testFinishedUpdateCycleDoesNotUnlockAlreadyStartedInstallation() {
        let gate = UpdateSafetyGate()
        var installs = 0
        gate.requestInstallation { installs += 1 }
        gate.cancelInstallation()
        XCTAssertEqual(installs, 1)
        XCTAssertTrue(gate.installationStarted)
        XCTAssertTrue(gate.blocksNewWork)
    }
}
