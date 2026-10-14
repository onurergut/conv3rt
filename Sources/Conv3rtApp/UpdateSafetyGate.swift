import Foundation
import Combine

@MainActor
final class UpdateSafetyGate: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var blocksNewWork = false
    private(set) var installationStarted = false
    private var work = Set<UUID>()
    private var installHandler: (() -> Void)?

    func beginWork(admitted: Bool = false) -> UUID? {
        guard !installationStarted, !blocksNewWork || admitted else { return nil }
        let token = UUID()
        work.insert(token)
        isBusy = true
        return token
    }

    func endWork(_ token: UUID) {
        guard work.remove(token) != nil else { return }
        isBusy = !work.isEmpty
        installIfIdle()
    }

    func requestInstallation(_ handler: @escaping () -> Void) {
        guard !blocksNewWork else { return }
        blocksNewWork = true
        installHandler = handler
        installIfIdle()
    }

    func cancelInstallation() {
        guard !installationStarted else { return }
        installHandler = nil
        blocksNewWork = false
    }

    func abortInstallation() {
        installHandler = nil
        installationStarted = false
        blocksNewWork = false
    }

    private func installIfIdle() {
        guard work.isEmpty, let handler = installHandler else { return }
        installHandler = nil
        installationStarted = true
        handler()
    }
}
