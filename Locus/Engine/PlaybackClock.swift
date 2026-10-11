import Foundation

struct PlaybackClock: Sendable {
    private let readNow: @Sendable () -> Double
    private let sleepAt: @Sendable (Double) async throws -> Void

    init(now: @escaping @Sendable () -> Double, sleepUntil: @escaping @Sendable (Double) async throws -> Void) {
        readNow = now
        sleepAt = sleepUntil
    }

    init() {
        let clock = ContinuousClock()
        let origin = clock.now
        self.init(now: {
            let elapsed = origin.duration(to: clock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
        }, sleepUntil: { deadline in
            try await clock.sleep(until: origin.advanced(by: .seconds(deadline)))
        })
    }

    var now: Double { readNow() }

    func sleep(until seconds: Double) async throws {
        try Task.checkCancellation()
        try await sleepAt(max(now, seconds))
        try Task.checkCancellation()
    }
}
