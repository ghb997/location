import XCTest
@testable import LocusCore

final class PairingAttemptPolicyTests: XCTestCase {
    @MainActor
    func testCancelledWorkerCannotPublishOrRestartUntilItActuallyReturns() async {
        let policy = PairingAttemptPolicy()
        let id = policy.begin()!
        XCTAssertTrue(policy.acceptsCallbacks(id: id))
        policy.cancel(id: id)
        XCTAssertFalse(policy.acceptsCallbacks(id: id))
        XCTAssertNil(policy.begin())
        XCTAssertTrue(policy.workerRunning)
        XCTAssertEqual(policy.finish(id: id), .cancelled)
        XCTAssertFalse(policy.workerRunning)
        XCTAssertNotNil(policy.begin())
    }

    @MainActor
    func testLateOldCallbacksDoNotAffectTheNewAttemptOrPublishItsFile() async {
        let policy = PairingAttemptPolicy()
        let old = policy.begin()!
        policy.cancel(id: old)
        XCTAssertEqual(policy.finish(id: old), .cancelled)
        let current = policy.begin()!
        XCTAssertFalse(policy.acceptsCallbacks(id: old))
        XCTAssertEqual(policy.finish(id: old), .ignored)
        XCTAssertTrue(policy.workerRunning)
        XCTAssertTrue(policy.acceptsCallbacks(id: current))
        XCTAssertEqual(policy.finish(id: current), .publish)
    }

    @MainActor
    func testOnlyTheSuccessfulCurrentAttemptCanPublishOnce() async {
        let policy = PairingAttemptPolicy()
        let id = policy.begin()!
        XCTAssertFalse(policy.acceptsCallbacks(id: UUID()))
        XCTAssertEqual(policy.finish(id: UUID()), .ignored)
        XCTAssertEqual(policy.finish(id: id), .publish)
        XCTAssertEqual(policy.finish(id: id), .ignored)
    }

    func testStopWhileConnectIsBlockingPreventsTheFollowingSetStage() {
        let control = NativeRequestControl(seconds: 30)
        var calls: [String] = []
        // Represents an in-flight C connect returning after Stop; the actual
        // production engine checks this same control before each later stage.
        calls.append("connect")
        control.cancel()
        if control.mayStartNextStage { calls.append("set") }
        XCTAssertEqual(calls, ["connect"])
    }

    func testConnectReturningAfterDeadlineCannotStartSimulationOrSet() {
        var now: TimeInterval = 0
        let control = NativeRequestControl(seconds: 30, clock: { now })
        var calls = ["connect"]
        now = 31
        if control.mayStartNextStage { calls.append("simulation"); calls.append("set") }
        XCTAssertEqual(calls, ["connect"])
    }
}
