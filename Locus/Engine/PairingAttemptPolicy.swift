import Foundation

@MainActor
final class PairingAttemptPolicy {
    enum Completion: Equatable { case ignored, cancelled, publish }
    private(set) var activeID: UUID?
    private(set) var workerRunning = false
    private var cancelled = false

    func begin() -> UUID? {
        guard !workerRunning else { return nil }
        let id = UUID()
        activeID = id
        workerRunning = true
        cancelled = false
        return id
    }

    func cancel(id: UUID) {
        guard activeID == id, workerRunning else { return }
        cancelled = true
    }

    func acceptsCallbacks(id: UUID) -> Bool {
        workerRunning && activeID == id && !cancelled
    }

    func finish(id: UUID) -> Completion {
        guard workerRunning, activeID == id else { return .ignored }
        let disposition: Completion = cancelled ? .cancelled : .publish
        workerRunning = false
        activeID = nil
        cancelled = false
        return disposition
    }
}
