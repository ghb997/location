import CoreLocation
import Foundation
import XCTest
@testable import LocusCore

/// These tests construct SpoofSession itself. Only platform services and time
/// are replaced, so retry ownership, repair gates and heartbeat wiring execute
/// the same code as the application.
@MainActor
final class SessionIntegrationTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)

    func testNewManualAndFavoriteTargetRejectLateSearchAndImport() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        let search = rig.session.beginTargetChange()
        let manual = CLLocationCoordinate2D(latitude: 30, longitude: 120)
        XCTAssertTrue(rig.session.selectTarget(manual, source: .manual))
        XCTAssertFalse(rig.session.selectTarget(origin, source: .appleSearch, replacing: search))
        XCTAssertEqual(rig.session.pin.map(RoutePoint.init), RoutePoint(manual))
        let imported = rig.session.beginTargetChange()
        rig.session.selectTarget(origin, source: .legacy)
        rig.session.teleport(to: origin, pairing: rig.pairing)
        XCTAssertFalse(rig.session.acceptsTargetChange(imported))
        await waitFor { rig.session.status == .active }
        XCTAssertEqual(rig.session.pinSource, .legacy)
    }

    func testDamagedFavoritesCannotBeOverwrittenThroughSession() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        let damaged = Data("damaged".utf8)
        rig.defaults.set(damaged, forKey: "locus.favorites")
        rig.session.reloadPlaces()
        XCTAssertTrue(rig.session.favoritesNeedRecovery)
        rig.session.addFavorite(name: "new", coordinate: origin)
        XCTAssertTrue(rig.session.favorites.isEmpty)
        XCTAssertEqual(rig.defaults.data(forKey: "locus.favorites"), damaged)
        XCTAssertNotNil(rig.session.lastError)
    }

    func testReopenedRouteWaitsForRestorationAndExplicitResume() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.draftTrack = RouteTrack(coordinates: [origin, .init(latitude: 31.24, longitude: 121.48)])
        rig.session.followRoute(rig.session.draftTrack!, pairing: rig.pairing)
        await waitFor { rig.session.routeState == .playing && rig.clock.pendingCount >= 2 }
        await advance(rig, by: 0.5)
        await waitFor { rig.session.routePlayback.completedDistance > 0 }
        rig.session.pauseRoute()
        await waitFor { rig.session.routeState == .paused }
        await rig.session.flushRoutePersistence()
        let confirmed = rig.session.routePlayback.completedDistance
        let transport = SessionTestTransport()
        let reopened = SpoofSession(clock: rig.clock.playbackClock, restorationStore: rig.store, transport: transport,
            runtime: SessionRuntime(locationKeeper: SessionTestKeeper(), monitorsNetwork: false,
                sendsNotifications: false, preferences: rig.defaults, targetIP: { "10.7.0.1" }))
        await waitFor { reopened.currentRoute != nil }
        XCTAssertEqual(reopened.routeState, .paused)
        XCTAssertEqual(reopened.routePlayback.completedDistance, confirmed)
        XCTAssertTrue(transport.writes.isEmpty)
        reopened.resumeRoute(pairing: rig.pairing)
        XCTAssertTrue(transport.writes.isEmpty)
        reopened.stop(pairing: rig.pairing)
        await waitFor { reopened.status == .idle }
        XCTAssertEqual(reopened.routeState, .paused)
        XCTAssertEqual(reopened.routePlayback.completedDistance, confirmed)
        reopened.resumeRoute(pairing: rig.pairing)
        await waitFor { reopened.routeState == .playing }
        XCTAssertEqual(transport.writes.first?.point, rig.session.simulated.map(RoutePoint.init))
        reopened.stop(pairing: rig.pairing)
        await waitFor { reopened.status == .idle }
        await reopened.flushRoutePersistence()
    }

    func testForegroundRecoversAfterRetryExhaustionAndRestartsHeartbeat() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.teleport(to: origin, pairing: rig.pairing)
        await waitFor { rig.session.status == .active && rig.clock.pendingCount > 0 }
        await exhaustRetries(rig)
        let confirmed = rig.session.simulated.map(RoutePoint.init)
        rig.transport.setResult = .success(())
        rig.session.handleForeground(pairing: rig.pairing)
        await waitFor { rig.transport.validations == 1 && rig.clock.pendingCount > 0 }
        await advance(rig, by: 1)
        await waitFor { rig.session.status == .active && rig.transport.writes.count == 6 }
        XCTAssertEqual(rig.transport.writes.last?.point, confirmed)
        await advance(rig, by: 8)
        await waitFor { rig.transport.writes.count == 7 }
        XCTAssertEqual(rig.transport.writes.last?.point, confirmed)
    }

    func testNetworkRecoveryKeepsRoutePausedAtConfirmedProgress() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.followRoute([origin, CLLocationCoordinate2D(latitude: 31.24, longitude: 121.48)], pairing: rig.pairing)
        await waitFor { rig.session.routeState == .playing && rig.clock.pendingCount >= 2 }
        rig.transport.setResult = .failure(.serviceUnreachable)
        await advance(rig, by: 0.5)
        await waitFor { rig.session.routeState == .paused && rig.transport.writes.count == 2 }
        let progress = rig.session.routePlayback
        let confirmed = rig.session.simulated.map(RoutePoint.init)
        for delay in RetrySchedule.delays {
            await advance(rig, by: delay)
        }
        await waitFor { rig.transport.writes.count == 5 && rig.clock.pendingCount == 0 }
        rig.transport.setResult = .success(())
        rig.session.networkPathChanged(signature: "reconnected", available: true)
        await settle()
        await advance(rig, by: 0.5)
        await waitFor { rig.transport.validations == 1 && rig.clock.pendingCount > 0 }
        await advance(rig, by: 1)
        await waitFor { rig.session.status == .active }
        XCTAssertEqual(rig.session.routePlayback, progress)
        XCTAssertEqual(rig.transport.writes.last?.point, confirmed)
        await advance(rig, by: 8)
        XCTAssertEqual(rig.session.routeState, .paused)
        XCTAssertEqual(rig.session.routePlayback.completedDistance, progress.completedDistance)
        XCTAssertEqual(rig.transport.writes.last?.point, confirmed)
    }

    func testStopRejectsLateSuccessfulValidationAndCancelsRetryRecovery() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.teleport(to: origin, pairing: rig.pairing)
        await waitFor { rig.session.status == .active && rig.clock.pendingCount > 0 }
        await exhaustRetries(rig)
        rig.transport.holdValidation = true
        rig.session.handleForeground(pairing: rig.pairing)
        await waitFor { rig.transport.hasPendingValidation }
        rig.session.stop(pairing: rig.pairing)
        await waitFor { rig.session.status == .idle }
        rig.transport.completeValidation(.success(()))
        await advance(rig, by: 60)
        XCTAssertEqual(rig.transport.writes.count, 5)
        XCTAssertEqual(rig.session.status, .idle)
        XCTAssertFalse(rig.store.hasPendingRecord)
        XCTAssertNil(rig.session.simulated)
        XCTAssertEqual(rig.keeper.freshRequests, 1)
    }

    func testStopCancelsNewRetryBeforeItsFirstWrite() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.teleport(to: origin, pairing: rig.pairing)
        await waitFor { rig.session.status == .active && rig.clock.pendingCount > 0 }
        await exhaustRetries(rig)
        rig.session.handleForeground(pairing: rig.pairing)
        await waitFor { rig.transport.validations == 1 && rig.clock.pendingCount > 0 }
        rig.session.stop(pairing: rig.pairing)
        await waitFor { rig.session.status == .idle }
        await advance(rig, by: 60)
        XCTAssertEqual(rig.transport.writes.count, 5)
        XCTAssertEqual(rig.clock.pendingCount, 0)
    }

    func testReachableEndpointStillUsesBoundedNativeRecoveryAttempts() async {
        let rig = SessionRig()
        defer { rig.dispose() }
        rig.session.teleport(to: origin, pairing: rig.pairing)
        await waitFor { rig.session.status == .active && rig.clock.pendingCount > 0 }
        await exhaustRetries(rig)
        rig.session.handleForeground(pairing: rig.pairing)
        await waitFor { rig.transport.validations == 1 && rig.clock.pendingCount > 0 }
        for (index, delay) in RetrySchedule.delays.enumerated() {
            await advance(rig, by: delay)
            await waitFor { rig.transport.writes.count == 6 + index && !rig.session.isBusy }
        }
        await waitFor { rig.clock.pendingCount == 0 }
        await advance(rig, by: 60)
        XCTAssertEqual(rig.transport.writes.count, 8)
        XCTAssertTrue(rig.session.status.isDropped)
        XCTAssertTrue(rig.store.hasPendingRecord)
    }

    func testRepairRetainsMarkerBlocksInjectionAndClearsUsingNewConfiguration() async {
        let record = RestorationRecord(point: RoutePoint(origin), pairingPath: "/missing/old.plist", deviceIP: "10.7.0.2")
        let rig = SessionRig(record: record)
        defer { rig.dispose() }
        // A running session can retain its last successful point after a drop.
        // The repair gate must block even this case, not just a fresh launch.
        rig.session.simulated = origin
        rig.pairing.hasPairingFile = false
        XCTAssertTrue(rig.session.beginRecoveryRepair())
        rig.session.teleport(to: origin, pairing: rig.pairing)
        XCTAssertFalse(rig.session.updateRecoveryConfiguration(targetIP: "10.7.0.3", pairing: rig.pairing))
        XCTAssertEqual(rig.store.record, record)
        rig.pairing.hasPairingFile = true
        rig.pairing.pairingPath = "/new/repaired.plist"
        XCTAssertTrue(rig.session.updateRecoveryConfiguration(targetIP: "10.7.0.3", pairing: rig.pairing))
        XCTAssertEqual(rig.transport.invalidations, 1)
        XCTAssertTrue(rig.store.hasPendingRecord)
        XCTAssertEqual(rig.store.record?.point, record.point)
        XCTAssertEqual(rig.store.record?.deviceIP, "10.7.0.3")
        rig.session.endRecoveryRepair()
        XCTAssertFalse(rig.session.canWrite)
        rig.session.teleport(to: origin, pairing: rig.pairing)
        rig.session.reconnect(pairing: rig.pairing)
        rig.session.startJoystick(pairing: rig.pairing)
        rig.session.followRoute([origin, CLLocationCoordinate2D(latitude: 31.24, longitude: 121.48)], pairing: rig.pairing)
        rig.session.handleForeground(pairing: rig.pairing)
        rig.session.networkPathChanged(signature: "new-network", available: true)
        await advance(rig, by: 60)
        XCTAssertTrue(rig.transport.writes.isEmpty)
        XCTAssertEqual(rig.transport.validations, 0)
        XCTAssertTrue(rig.store.hasPendingRecord)
        rig.session.stop(pairing: rig.pairing)
        await waitFor { rig.session.status == .idle }
        XCTAssertEqual(rig.transport.clears.last?.ip, "10.7.0.3")
        XCTAssertEqual(rig.transport.clears.last?.path, "/new/repaired.plist")
        XCTAssertFalse(rig.store.hasPendingRecord)
        XCTAssertTrue(rig.session.canWrite)
    }

    func testRepairCannotReplaceMarkerWhenTransportCannotInvalidate() async {
        let record = RestorationRecord(point: RoutePoint(origin), pairingPath: "/old.plist", deviceIP: "10.7.0.2")
        let rig = SessionRig(record: record)
        defer { rig.dispose() }
        XCTAssertTrue(rig.session.beginRecoveryRepair())
        rig.transport.canInvalidate = false
        XCTAssertFalse(rig.session.updateRecoveryConfiguration(targetIP: "10.7.0.3", pairing: rig.pairing))
        XCTAssertEqual(rig.store.record, record)
        XCTAssertTrue(rig.session.restorationRequired)
    }

    func testRepairWithCorruptMarkerPreservesUnknownCoordinateUntilClear() async {
        let rig = SessionRig(corruptMarker: true)
        defer { rig.dispose() }
        XCTAssertTrue(rig.session.restorationRequired)
        XCTAssertTrue(rig.session.beginRecoveryRepair())
        XCTAssertTrue(rig.session.updateRecoveryConfiguration(targetIP: "10.7.0.4", pairing: rig.pairing))
        XCTAssertTrue(rig.store.hasPendingRecord)
        XCTAssertNil(rig.store.record?.point)
        rig.session.endRecoveryRepair()
        rig.transport.clearResult = .failure(.locationClear)
        rig.session.stop(pairing: rig.pairing)
        await waitFor { rig.session.status.isDropped && !rig.session.isBusy }
        XCTAssertTrue(rig.store.hasPendingRecord)
        XCTAssertFalse(rig.session.canWrite)
        XCTAssertTrue(rig.transport.writes.isEmpty)
    }

    func testDrainingOrPendingStopCannotEnterRepair() async {
        let rig = SessionRig(record: RestorationRecord(point: RoutePoint(origin), pairingPath: "/record.plist", deviceIP: "10.7.0.1"))
        defer { rig.dispose() }
        rig.transport.isDraining = true
        XCTAssertFalse(rig.session.beginRecoveryRepair())
        rig.transport.isDraining = false
        rig.transport.isStopPending = true
        XCTAssertFalse(rig.session.beginRecoveryRepair())
        rig.transport.isStopPending = false
        XCTAssertTrue(rig.session.beginRecoveryRepair())
    }

    private func exhaustRetries(_ rig: SessionRig) async {
        rig.transport.setResult = .failure(.serviceUnreachable)
        rig.session.reconnect(pairing: rig.pairing)
        await waitFor { rig.transport.writes.count == 2 && !rig.session.isBusy }
        await settle()
        for (index, delay) in RetrySchedule.delays.enumerated() {
            await advance(rig, by: delay)
            await waitFor { rig.transport.writes.count == index + 3 && !rig.session.isBusy }
        }
        await waitFor { rig.clock.pendingCount == 0 }
        XCTAssertTrue(rig.session.status.isDropped)
    }

    private func advance(_ rig: SessionRig, by seconds: Double) async {
        await settle()
        rig.clock.advance(by: seconds)
        await settle()
    }

    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func waitFor(file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Session did not reach the expected state", file: file, line: line)
    }
}

@MainActor
private final class SessionRig {
    let clock = SessionTestClock()
    let transport = SessionTestTransport()
    let keeper = SessionTestKeeper()
    let pairing = SessionTestPairing()
    let suite = "LocusSessionIntegration.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: RestorationRecordStore
    let session: SpoofSession

    init(record: RestorationRecord? = nil, corruptMarker: Bool = false) {
        let preferences = UserDefaults(suiteName: suite)!
        defaults = preferences
        store = RestorationRecordStore(defaults: preferences, key: "pending")
        if let record { store.save(record) }
        if corruptMarker { preferences.set(Data("broken".utf8), forKey: "pending") }
        session = SpoofSession(clock: clock.playbackClock, restorationStore: store, transport: transport,
                               runtime: SessionRuntime(locationKeeper: keeper, monitorsNetwork: false,
                                                       sendsNotifications: false, preferences: preferences,
                                                       targetIP: { "10.7.0.1" }))
    }

    func dispose() {
        session.endRecoveryRepair()
        transport.completeValidation(.failure(.operationCancelled))
        session.stop(pairing: pairing)
        clock.cancelAll()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class SessionTestPairing: PairingProviding {
    var hasPairingFile = true
    var pairingPath = "/pairing.plist"
}

@MainActor
private final class SessionTestKeeper: LocationKeeping {
    var onFix: ((SystemLocationFix?) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?
    var onIssue: ((String?) -> Void)?
    var freshRequests = 0
    func start() {}
    func stop() {}
    func requestFreshSystemFix() { freshRequests += 1 }
    func setSimulationActive(_ active: Bool) {}
    func setBackgroundEnabled(_ enabled: Bool) {}
}

@MainActor
private final class SessionTestTransport: LocationTransport {
    struct Write { let point: RoutePoint; let path: String; let ip: String }
    struct Clear { let path: String?; let ip: String? }
    var isStopPending = false
    var isDraining = false
    var writes: [Write] = []
    var clears: [Clear] = []
    var validations = 0
    var invalidations = 0
    var canInvalidate = true
    var setResult: Result<Void, LocationEngineError> = .success(())
    var clearResult: Result<Void, LocationEngineError> = .success(())
    var holdValidation = false
    private var pendingValidation: CheckedContinuation<Result<Void, LocationEngineError>, Never>?
    var hasPendingValidation: Bool { pendingValidation != nil }

    func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        writes.append(Write(point: RoutePoint(latitude: latitude, longitude: longitude), path: pairingPath, ip: deviceIP))
        return setResult
    }
    func clear(pairingPath: String?, deviceIP: String?) async -> Result<Void, LocationEngineError> {
        clears.append(Clear(path: pairingPath, ip: deviceIP))
        return clearResult
    }
    func validateConnection(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        validations += 1
        if holdValidation { return await withCheckedContinuation { pendingValidation = $0 } }
        return .success(())
    }
    func completeValidation(_ result: Result<Void, LocationEngineError>) {
        let pending = pendingValidation
        pendingValidation = nil
        pending?.resume(returning: result)
    }
    func cancelPendingPreparation() {}
    func invalidateConnectionForRecovery() -> Bool { invalidations += 1; return canInvalidate }
}

private final class SessionTestClock: @unchecked Sendable {
    private struct Waiter {
        let deadline: Double
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var instant = 0.0
    private var waiters: [UUID: Waiter] = [:]
    private var cancelled: Set<UUID> = []

    var now: Double { lock.withLock { instant } }
    var pendingCount: Int { lock.withLock { waiters.count } }
    var playbackClock: PlaybackClock {
        PlaybackClock(now: { self.now }, sleepUntil: { try await self.sleep(until: $0) })
    }

    func advance(by seconds: Double) {
        let ready: [Waiter] = lock.withLock {
            instant += seconds
            let ready = waiters.filter { $0.value.deadline <= instant }
            for key in ready.keys { waiters.removeValue(forKey: key) }
            return Array(ready.values)
        }
        ready.forEach { $0.continuation.resume() }
    }

    private func sleep(until deadline: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(id, deadline: deadline, continuation: continuation)
            }
        } onCancel: { self.cancel(id) }
    }

    private func register(_ id: UUID, deadline: Double, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if cancelled.remove(id) != nil {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
        } else if deadline <= instant {
            lock.unlock()
            continuation.resume()
        } else {
            waiters[id] = Waiter(deadline: deadline, continuation: continuation)
            lock.unlock()
        }
    }

    private func cancel(_ id: UUID) {
        let waiter: Waiter? = lock.withLock {
            if let waiter = waiters.removeValue(forKey: id) { return waiter }
            cancelled.insert(id)
            return nil
        }
        waiter?.continuation.resume(throwing: CancellationError())
    }

    func cancelAll() {
        let pending: [Waiter] = lock.withLock {
            let pending = Array(waiters.values)
            waiters.removeAll()
            return pending
        }
        pending.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}
