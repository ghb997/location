import XCTest
@testable import LocusCore

final class PairingAudioPolicyTests: XCTestCase {
    func testAudioIsOptInAndCannotStartTwice() {
        var policy = PairingAudioPolicy()
        XCTAssertNil(policy.begin(enabled: false))
        XCTAssertFalse(policy.requested)
        XCTAssertNotNil(policy.begin(enabled: true))
        XCTAssertNil(policy.begin(enabled: true))
    }

    func testCancelledAttemptCannotResumeFromLateInterruptionOrReset() {
        var policy = PairingAudioPolicy()
        let old = policy.begin(enabled: true)!
        XCTAssertTrue(policy.interruptionBegan(token: old))
        policy.stop()
        XCTAssertFalse(policy.interruptionEnded(token: old, shouldResume: true))
        XCTAssertFalse(policy.mayRecoverAfterReset(token: old))
        let next = policy.begin(enabled: true)!
        XCTAssertNotEqual(next, old)
        XCTAssertFalse(policy.interruptionBegan(token: old))
        XCTAssertTrue(policy.mayRecoverAfterReset(token: next))
    }

    func testAudioRespectsSystemResumePermissionAndResetDuringInterruption() {
        var policy = PairingAudioPolicy()
        let token = policy.begin(enabled: true)!
        XCTAssertTrue(policy.interruptionBegan(token: token))
        XCTAssertFalse(policy.mayRecoverAfterReset(token: token))
        XCTAssertFalse(policy.interruptionEnded(token: token, shouldResume: false))
        XCTAssertFalse(policy.mayRecoverAfterReset(token: token))
        XCTAssertTrue(policy.interruptionEnded(token: token, shouldResume: true))
        XCTAssertTrue(policy.mayRecoverAfterReset(token: token))
    }
}
