import Foundation

/// Owns one bounded request for a post-request, non-simulated system location.
/// Every provider attempt has a distinct identity, so an old delegate or sleep
/// can never finish a newer request. The deadline uses monotonic time.
@MainActor
final class FreshLocationController {
    enum State: Equatable {
        case idle
        case waiting(attempt: Int)
        case retrying
        case succeeded
        case timedOut
    }

    private let clock: PlaybackClock
    private let wallNow: () -> Date
    private let request: (UUID) -> Void
    private let cancelRequest: () -> Void
    private let maximumAttempts: Int
    private let attemptInterval: Double
    private var generation = UUID()
    private var requestID: UUID?
    private var requestedAt: Date?
    private var expiresAt: Double?
    private var attempt = 0
    private var deadlineTask: Task<Void, Never>?
    private(set) var state: State = .idle
    var onState: ((State) -> Void)?

    var isWaiting: Bool {
        switch state {
        case .waiting, .retrying: return true
        case .idle, .succeeded, .timedOut: return false
        }
    }

    init(clock: PlaybackClock = PlaybackClock(), wallNow: @escaping () -> Date = Date.init,
         maximumAttempts: Int = 3, attemptInterval: Double = 5,
         request: @escaping (UUID) -> Void, cancelRequest: @escaping () -> Void) {
        precondition(maximumAttempts > 0 && attemptInterval > 0 && attemptInterval.isFinite)
        self.clock = clock
        self.wallNow = wallNow
        self.maximumAttempts = maximumAttempts
        self.attemptInterval = attemptInterval
        self.request = request
        self.cancelRequest = cancelRequest
    }

    deinit { deadlineTask?.cancel() }

    func start() {
        cancel()
        let token = generation
        let started = clock.now
        requestedAt = wallNow()
        expiresAt = started + Double(maximumAttempts) * attemptInterval
        let clock = clock
        let maximumAttempts = maximumAttempts
        let attemptInterval = attemptInterval
        deadlineTask = Task { @MainActor [weak self] in
            for boundary in 1...maximumAttempts {
                do { try await clock.sleep(until: started + Double(boundary) * attemptInterval) }
                catch { return }
                guard let self, self.generation == token, self.isWaiting else { return }
                guard let expiresAt = self.expiresAt, clock.now < expiresAt,
                      boundary < maximumAttempts else {
                    self.finish(.timedOut)
                    return
                }
                self.beginAttempt()
            }
        }
        beginAttempt()
    }

    func cancel() {
        generation = UUID()
        requestID = nil
        requestedAt = nil
        expiresAt = nil
        attempt = 0
        deadlineTask?.cancel()
        deadlineTask = nil
        cancelRequest()
        setState(.idle)
    }

    /// Returns true only when this exact attempt supplied a usable fresh fix.
    @discardableResult
    func receive(requestID: UUID, timestamp: Date, horizontalAccuracy: Double,
                 isSimulated: Bool) -> Bool {
        guard self.requestID == requestID, isWaiting else { return false }
        guard let expiresAt, clock.now < expiresAt else {
            finish(.timedOut)
            return false
        }
        guard let requestedAt, timestamp >= requestedAt,
              horizontalAccuracy.isFinite, horizontalAccuracy >= 0, !isSimulated else {
            fail(requestID: requestID)
            return false
        }
        finish(.succeeded)
        return true
    }

    func fail(requestID: UUID) {
        guard self.requestID == requestID, isWaiting else { return }
        self.requestID = nil
        cancelRequest()
        if attempt >= maximumAttempts || clock.now >= (expiresAt ?? 0) {
            finish(.timedOut)
        } else {
            setState(.retrying)
        }
    }

    private func beginAttempt() {
        cancelRequest()
        attempt += 1
        let identifier = UUID()
        requestID = identifier
        setState(.waiting(attempt: attempt))
        request(identifier)
    }

    private func finish(_ result: State) {
        generation = UUID()
        requestID = nil
        requestedAt = nil
        expiresAt = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        cancelRequest()
        setState(result)
    }

    private func setState(_ state: State) {
        self.state = state
        onState?(state)
    }
}
