import Foundation

/// Cancellation is checked between synchronous native stages. It never frees a
/// handle while the native library is using it.
final class NativeRequestControl: @unchecked Sendable {
    enum Purpose: Equatable { case write, restoration }
    private let lock = NSLock()
    private var cancelled = false
    private let clock: () -> TimeInterval
    private let deadline: TimeInterval
    private let purpose: Purpose
    init(seconds: TimeInterval, purpose: Purpose = .write,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        self.purpose = purpose
        deadline = clock() + seconds
    }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var hasExpired: Bool { clock() >= deadline }
    var remainingSeconds: TimeInterval { max(0, deadline - clock()) }
    // Restoration must still clear an already submitted write when the serial
    // queue reaches it after the UI watchdog. Each native call keeps its own
    // bounded timeout; the watchdog only reports an unconfirmed draining state.
    var mayStartNextStage: Bool { !isCancelled && (purpose == .restoration || !hasExpired) }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
