import Foundation
import XCTest
@testable import LocusCore

final class SessionRecoveryPolicyTests: XCTestCase {
    private func makeStore() -> (RestorationRecordStore, UserDefaults, String) {
        let suite = "LocusRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (RestorationRecordStore(defaults: defaults, key: "pending"), defaults, suite)
    }

    private var validRecord: RestorationRecord {
        RestorationRecord(point: RoutePoint(latitude: 31.2304, longitude: 121.4737),
                          pairingPath: "/documents/device.plist", deviceIP: "10.7.0.2")
    }

    func testRestoreRecordSurvivesReloadUntilExplicitConfirmedClear() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.save(validRecord))
        let relaunched = RestorationRecordStore(defaults: defaults, key: "pending")
        XCTAssertTrue(relaunched.hasPendingRecord)
        XCTAssertEqual(relaunched.record, validRecord)
        relaunched.clear()
        XCTAssertNil(store.record)
        XCTAssertFalse(store.hasPendingRecord)
    }

    func testInvalidReplacementCannotEraseExistingRecoveryInformation() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.save(validRecord))
        var invalid = validRecord
        invalid.point.latitude = .nan
        XCTAssertFalse(store.save(invalid))
        invalid = validRecord
        invalid.deviceIP = "256.2.3.4"
        XCTAssertFalse(store.save(invalid))
        invalid = validRecord
        invalid.pairingPath = "   "
        XCTAssertFalse(store.save(invalid))
        XCTAssertEqual(store.record, validRecord)
    }

    func testCorruptMarkerStillRequiresRecovery() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: "pending")
        XCTAssertNil(store.record)
        XCTAssertTrue(store.hasPendingRecord)
        defaults.set("wrong data type", forKey: "pending")
        XCTAssertNil(store.record)
        XCTAssertTrue(store.hasPendingRecord)
    }

    func testRetryBudgetIsExactlyThreeAndCancellationStopsFurtherDelays() {
        var retries = RetrySchedule()
        XCTAssertEqual(retries.nextDelay(), 1)
        XCTAssertEqual(retries.nextDelay(), 3)
        XCTAssertEqual(retries.nextDelay(), 8)
        XCTAssertNil(retries.nextDelay())
        XCTAssertEqual(retries.attempts, 3)
        var cancelled = RetrySchedule()
        XCTAssertEqual(cancelled.nextDelay(), 1)
        cancelled.cancel()
        XCTAssertNil(cancelled.nextDelay())
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(cancelled.attempts, 1)
    }

    func testStopRejectsOldPreparationAndWriteCompletion() {
        var epoch = SessionOperationEpoch()
        let preparing = epoch.value
        XCTAssertTrue(epoch.accepts(preparing))
        let stop = epoch.invalidate()
        XCTAssertFalse(epoch.accepts(preparing))
        XCTAssertTrue(epoch.accepts(stop))
        let nextSession = epoch.invalidate()
        XCTAssertFalse(epoch.accepts(stop))
        XCTAssertTrue(epoch.accepts(nextSession))
    }

    func testCancelledRetryCannotReleaseReplacementOwnership() {
        var retryEpoch = SessionOperationEpoch()
        let oldRun = retryEpoch.invalidate()
        retryEpoch.invalidate()
        let replacement = retryEpoch.invalidate()
        XCTAssertFalse(retryEpoch.accepts(oldRun))
        XCTAssertTrue(retryEpoch.accepts(replacement))
    }
}
