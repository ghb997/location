import Foundation
import XCTest
@testable import LocusCore

final class PlaybackClockTests: XCTestCase {
    func testInjectedClockUsesAbsoluteDeadlineAndClampsPastSleep() async throws {
        let state = TestClockState(now: 100)
        let clock = PlaybackClock(now: { state.now }, sleepUntil: { state.advance(to: $0) })
        XCTAssertEqual(clock.now, 100)
        try await clock.sleep(until: 100.5)
        XCTAssertEqual(clock.now, 100.5)
        try await clock.sleep(until: 99)
        XCTAssertEqual(state.deadlines, [100.5, 100.5])
        try await clock.sleep(until: 101)
        XCTAssertEqual(clock.now, 101)
    }

    func testCancellationAfterUncooperativeSleepCannotAdvancePlayback() async {
        let gate = ClockGate()
        let clock = PlaybackClock(now: { 0 }, sleepUntil: { _ in await gate.sleep() })
        let task = Task { try await clock.sleep(until: 0.5) }
        await gate.waitUntilSleeping()
        task.cancel()
        await gate.release()
        do { try await task.value; XCTFail("Cancelled sleep returned normally") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class TestClockState: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double
    private var recorded: [Double] = []
    init(now: Double) { time = now }
    var now: Double { lock.lock(); defer { lock.unlock() }; return time }
    var deadlines: [Double] { lock.lock(); defer { lock.unlock() }; return recorded }
    func advance(to deadline: Double) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(deadline)
        time = deadline
    }
}

private actor ClockGate {
    private var sleeping = false
    private var watchers: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?
    func sleep() async {
        sleeping = true
        watchers.forEach { $0.resume() }
        watchers.removeAll()
        await withCheckedContinuation { completion = $0 }
    }
    func waitUntilSleeping() async {
        if sleeping { return }
        await withCheckedContinuation { watchers.append($0) }
    }
    func release() { completion?.resume(); completion = nil }
}
