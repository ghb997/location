import Foundation

/// Notification callbacks from a previous pairing must not restart its audio.
struct PairingAudioPolicy {
    private(set) var generation = 0
    private(set) var requested = false
    private(set) var interrupted = false

    mutating func begin(enabled: Bool) -> Int? {
        guard enabled, !requested else { return nil }
        generation &+= 1
        requested = true
        interrupted = false
        return generation
    }

    func accepts(_ token: Int) -> Bool { requested && generation == token }

    mutating func interruptionBegan(token: Int) -> Bool {
        guard accepts(token) else { return false }
        interrupted = true
        return true
    }

    mutating func interruptionEnded(token: Int, shouldResume: Bool) -> Bool {
        guard accepts(token) else { return false }
        interrupted = !shouldResume
        return shouldResume
    }

    func mayRecoverAfterReset(token: Int) -> Bool { accepts(token) && !interrupted }

    mutating func stop() {
        generation &+= 1
        requested = false
        interrupted = false
    }
}
