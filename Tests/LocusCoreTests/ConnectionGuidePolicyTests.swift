import XCTest
@testable import LocusCore

final class ConnectionGuidePolicyTests: XCTestCase {
    func testNativeWaitWinsOverRecoveryAndMissingPairing() {
        let guide = ConnectionGuidePolicy.resolve(.init(
            hasPairingFile: false, nativeDraining: true, restorationRequired: true,
            canRetryRestore: true, session: .interrupted, service: .failed))
        XCTAssertEqual(guide.topic, .nativeWaiting)
        XCTAssertEqual(guide.settingsSection, .diagnostics)
        XCTAssertFalse(guide.canCheckConnection)
        XCTAssertFalse(guide.canRestoreLocation)
    }

    func testMissingPairingDoesNotHideAnOutstandingRecoveryRecord() {
        let guide = ConnectionGuidePolicy.resolve(.init(
            hasPairingFile: false, restorationRequired: true, canRetryRestore: true))
        XCTAssertEqual(guide.topic, .restoration)
        XCTAssertEqual(guide.settingsSection, .restoration)
        XCTAssertFalse(guide.canRestoreLocation)
        XCTAssertFalse(guide.canCheckConnection)
    }

    func testPairingWorkerHasItsOwnWaitingInstructions() {
        let guide = ConnectionGuidePolicy.resolve(.init(hasPairingFile: false, pairingWorkerRunning: true))
        XCTAssertEqual(guide.topic, .pairingWaiting)
        XCTAssertEqual(guide.settingsSection, .pairing)
        XCTAssertFalse(guide.canCheckConnection)
    }

    func testBusyConnectionAndStopCannotOfferAnotherOperation() {
        let busyStates: [ConnectionGuidePolicy.SessionState] = [.connecting, .reconnecting, .stopping]
        for state in busyStates {
            let guide = ConnectionGuidePolicy.resolve(.init(
                hasPairingFile: true, canRetryRestore: true, session: state, service: .ready))
            XCTAssertFalse(guide.canCheckConnection)
            XCTAssertFalse(guide.canRestoreLocation)
            XCTAssertNotEqual(guide.topic, .ready)
        }
    }

    func testServiceReachabilityNeverClaimsDeveloperReadiness() {
        let reachable = ConnectionGuidePolicy.resolve(.init(hasPairingFile: true, service: .reachable))
        let ready = ConnectionGuidePolicy.resolve(.init(hasPairingFile: true, service: .ready))
        XCTAssertEqual(reachable.topic, .reachable)
        XCTAssertEqual(ready.topic, .ready)
        XCTAssertNotEqual(reachable.titleKey, ready.titleKey)
        XCTAssertNotEqual(reachable.summaryKey, ready.summaryKey)
    }

    func testCurrentSessionOutranksAStaleDiagnosticResult() {
        let interrupted = ConnectionGuidePolicy.resolve(.init(
            hasPairingFile: true, session: .interrupted, service: .ready))
        XCTAssertEqual(interrupted.topic, .interrupted)
        let active = ConnectionGuidePolicy.resolve(.init(
            hasPairingFile: true, session: .active, service: .failed))
        XCTAssertEqual(active.topic, .active)
    }

    func testLiveRecoveryMarkerDoesNotMislabelAnActiveOrProgressingSession() {
        let cases: [(ConnectionGuidePolicy.SessionState, ConnectionGuidePolicy.Topic)] = [
            (.active, .active), (.connecting, .connecting), (.reconnecting, .reconnecting), (.stopping, .stopping)
        ]
        for (session, topic) in cases {
            let guide = ConnectionGuidePolicy.resolve(.init(
                hasPairingFile: true, restorationRequired: true, canRetryRestore: true,
                session: session, service: .ready))
            XCTAssertEqual(guide.topic, topic)
            XCTAssertFalse(guide.canRestoreLocation)
        }
    }

    func testRestoreRequiresBothRecoveryAndTheSessionPermission() {
        var state = ConnectionGuidePolicy.Snapshot(hasPairingFile: true, restorationRequired: true)
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
        state.canRetryRestore = true
        XCTAssertTrue(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
        state.restorationRequired = false
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
        state.restorationRequired = true
        state.isBusy = true
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
        state.isBusy = false
        state.pairingWorkerRunning = true
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
        state.pairingWorkerRunning = false
        state.service = .checking
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canRestoreLocation)
    }

    func testCheckIsDisabledDuringDiagnosticWorkAndMissingPairing() {
        var state = ConnectionGuidePolicy.Snapshot(hasPairingFile: true)
        XCTAssertTrue(ConnectionGuidePolicy.resolve(state).canCheckConnection)
        state.service = .checking
        XCTAssertEqual(ConnectionGuidePolicy.resolve(state).topic, .checking)
        XCTAssertFalse(ConnectionGuidePolicy.resolve(state).canCheckConnection)
        state.service = .unknown
        state.hasPairingFile = false
        let guide = ConnectionGuidePolicy.resolve(state)
        XCTAssertEqual(guide.topic, .pairing)
        XCTAssertEqual(guide.settingsSection, .pairing)
        XCTAssertFalse(guide.canCheckConnection)
    }
}
