import Foundation
import XCTest
@testable import LocusCore

@MainActor
final class FreshLocationControllerTests: XCTestCase {
    func testCachedResultSchedulesRetryAndFreshResultCompletes() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let first = harness.requests[0]
        XCTAssertFalse(harness.receive(first, timestamp: harness.requestDate.addingTimeInterval(-1)))
        XCTAssertEqual(harness.controller.state, .retrying)
        XCTAssertNil(harness.activeRequest)
        harness.time.advance(to: 5)
        await eventually { harness.requests.count == 2 }
        XCTAssertTrue(harness.receive(harness.requests[1]))
        XCTAssertEqual(harness.controller.state, .succeeded)
        XCTAssertNil(harness.activeRequest)
        harness.time.advance(to: 100)
        await drainTasks()
        XCTAssertEqual(harness.requests.count, 2)
        XCTAssertEqual(harness.controller.state, .succeeded)
    }

    func testNoCallbackTimesOutAtFifteenSecondsWithOnlyThreeRequests() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        harness.time.advance(to: 5)
        await eventually { harness.requests.count == 2 }
        harness.time.advance(to: 10)
        await eventually { harness.requests.count == 3 }
        harness.time.advance(to: 15)
        await eventually { harness.controller.state == .timedOut }
        XCTAssertNil(harness.activeRequest)
        XCTAssertFalse(harness.controller.isWaiting)
        XCTAssertEqual(harness.requests.count, 3)
        XCTAssertFalse(harness.overlappedRequests)
    }

    func testOldAttemptCannotCompleteOrFailNewAttempt() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let old = harness.requests[0]
        harness.time.advance(to: 5)
        await eventually { harness.requests.count == 2 }
        let current = harness.requests[1]
        XCTAssertFalse(harness.receive(old))
        harness.controller.fail(requestID: old)
        XCTAssertEqual(harness.controller.state, .waiting(attempt: 2))
        XCTAssertEqual(harness.activeRequest, current)
        XCTAssertTrue(harness.receive(current))
    }

    func testStopOrSimulationCancellationRejectsLateFixAndSleepingRetry() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let cancelled = harness.requests[0]
        harness.controller.cancel()
        XCTAssertFalse(harness.receive(cancelled))
        harness.controller.fail(requestID: cancelled)
        harness.time.advance(to: 100)
        await drainTasks()
        XCTAssertEqual(harness.controller.state, .idle)
        XCTAssertEqual(harness.requests.count, 1)
        XCTAssertNil(harness.activeRequest)
    }

    func testRestartAfterPermissionChangeIgnoresPreviousDeadlineAndResult() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let cancelled = harness.requests[0]
        harness.time.advance(to: 4)
        harness.controller.cancel()
        harness.requestDate = harness.requestDate.addingTimeInterval(4)
        harness.controller.start()
        let current = harness.requests[1]
        XCTAssertFalse(harness.receive(cancelled))
        harness.time.advance(to: 5)
        await drainTasks()
        XCTAssertEqual(harness.controller.state, .waiting(attempt: 1))
        XCTAssertEqual(harness.requests.count, 2)
        XCTAssertTrue(harness.receive(current))
    }

    func testSimulatedOrInvalidFixesNeverCountAsRestoredSystemLocation() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        XCTAssertFalse(harness.receive(harness.requests[0], isSimulated: true))
        harness.time.advance(to: 5)
        await eventually { harness.requests.count == 2 }
        XCTAssertFalse(harness.receive(harness.requests[1], accuracy: .nan))
        harness.time.advance(to: 10)
        await eventually { harness.requests.count == 3 }
        XCTAssertFalse(harness.receive(harness.requests[2], accuracy: -1))
        XCTAssertEqual(harness.controller.state, .timedOut)
        XCTAssertNil(harness.activeRequest)
    }

    func testProviderFailureRetriesAndDoesNotLeaveWaitingForever() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        harness.controller.fail(requestID: harness.requests[0])
        XCTAssertEqual(harness.controller.state, .retrying)
        harness.time.advance(to: 5)
        await eventually { harness.requests.count == 2 }
        harness.controller.fail(requestID: harness.requests[1])
        harness.time.advance(to: 10)
        await eventually { harness.requests.count == 3 }
        harness.controller.fail(requestID: harness.requests[2])
        XCTAssertEqual(harness.controller.state, .timedOut)
        XCTAssertEqual(harness.requests.count, 3)
    }

    func testDeadlineIsEnforcedBeforeAcceptingLateCallbackEvenIfTimerHasNotRun() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let request = harness.requests[0]
        harness.time.advance(to: 15)
        XCTAssertFalse(harness.receive(request))
        XCTAssertEqual(harness.controller.state, .timedOut)
        XCTAssertEqual(harness.requests.count, 1)
    }

    func testLongSuspensionExpiresWithoutBurstingThroughMissedRetries() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        harness.time.advance(to: 60)
        await eventually { harness.controller.state == .timedOut }
        XCTAssertEqual(harness.requests.count, 1)
        XCTAssertNil(harness.activeRequest)
    }

    func testUserCanRetryAfterTimeoutAndOlderCallbackCannotReplaceFreshFix() async {
        let harness = FreshRequestHarness()
        defer { harness.cleanup() }
        harness.controller.start()
        let old = harness.requests[0]
        harness.time.advance(to: 15)
        await eventually { harness.controller.state == .timedOut }
        harness.controller.start()
        let current = harness.requests[1]
        XCTAssertFalse(harness.receive(old))
        XCTAssertTrue(harness.receive(current))
        XCTAssertFalse(harness.receive(old))
        XCTAssertEqual(harness.controller.state, .succeeded)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Scheduled request did not reach its expected state", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class FreshRequestHarness {
    let time = FreshTestClock()
    var requestDate = Date(timeIntervalSince1970: 100)
    var requests: [UUID] = []
    var activeRequest: UUID?
    var overlappedRequests = false
    lazy var controller = FreshLocationController(
        clock: PlaybackClock(now: { [time] in time.now }, sleepUntil: { [time] in await time.sleep(until: $0) }),
        wallNow: { [weak self] in self?.requestDate ?? .distantPast },
        request: { [weak self] identifier in
            guard let self else { return }
            if activeRequest != nil { overlappedRequests = true }
            activeRequest = identifier
            requests.append(identifier)
        },
        cancelRequest: { [weak self] in self?.activeRequest = nil }
    )

    func receive(_ identifier: UUID, timestamp: Date? = nil, accuracy: Double = 25, isSimulated: Bool = false) -> Bool {
        controller.receive(requestID: identifier, timestamp: timestamp ?? requestDate,
                           horizontalAccuracy: accuracy, isSimulated: isSimulated)
    }

    func cleanup() {
        controller.cancel()
        time.advance(to: 1_000)
    }
}

/// Deliberately ignores cancellation to verify stale sleeps cannot revive work.
private final class FreshTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = 0.0
    private var sleepers: [(Double, CheckedContinuation<Void, Never>)] = []
    var now: Double { lock.lock(); defer { lock.unlock() }; return time }

    func sleep(until deadline: Double) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if time >= deadline {
                lock.unlock()
                continuation.resume()
            } else {
                sleepers.append((deadline, continuation))
                lock.unlock()
            }
        }
    }

    func advance(to time: Double) {
        lock.lock()
        self.time = time
        let ready = sleepers.filter { $0.0 <= time }
        sleepers.removeAll { $0.0 <= time }
        lock.unlock()
        ready.forEach { $0.1.resume() }
    }
}
