import Foundation
import XCTest
@testable import LocusCore

final class RouteWorkspaceStoreTests: XCTestCase {
    private let draftKey = "location.routeDraft.v1"
    private let archiveKey = "location.routeArchive.v1"
    private let checkpointKey = "location.routeCheckpoint.v1"

    func testReopenPreservesConfirmedProgressAndTimingWithoutAdvancingWhileClosed() async throws {
        try await withStore { _, store in
            var original = RoutePlaybackCore(track: self.track(), speed: 2, variation: { 1 })
            store.saveDraft(original.track)
            store.saveRoute(original, includeArchive: true)
            original.start(at: 100)
            let confirmed = try XCTUnwrap(original.proposedSample(at: 100.5))
            original.confirm(confirmed, at: 100.8, writeStartedAt: 100.5)
            store.saveRoute(original, includeArchive: false)

            let loaded = await store.load()
            var restored = try XCTUnwrap(loaded.core)
            XCTAssertFalse(loaded.damaged)
            XCTAssertEqual(loaded.draft, original.track)
            XCTAssertEqual(restored.playbackID, original.playbackID)
            XCTAssertEqual(restored.snapshot.status, .paused)
            XCTAssertEqual(restored.confirmed, confirmed)
            XCTAssertEqual(restored.snapshot.progress, original.snapshot.progress)
            XCTAssertEqual(restored.plan?.cumulativeTime, original.plan?.cumulativeTime)
            XCTAssertNil(restored.proposedSample(at: 86_400))
            restored.start(at: 86_400)
            XCTAssertEqual(try XCTUnwrap(restored.proposedSample(at: 86_400.5)).elapsed, 1, accuracy: 1e-9)
        }
    }

    func testSameTrackNewTimingPlanCannotBorrowAnOlderArchiveCheckpoint() async throws {
        try await withStore { _, store in
            let track = self.track()
            let slow = RoutePlaybackCore(track: track, speed: 2, variation: { 1 })
            var fast = RoutePlaybackCore(track: track, speed: 5, variation: { 1.1 })
            XCTAssertEqual(slow.track.id, fast.track.id)
            XCTAssertNotEqual(slow.playbackID, fast.playbackID)
            store.saveRoute(slow, includeArchive: true)
            fast.start(at: 0)
            let fastSample = try XCTUnwrap(fast.proposedSample(at: 0.5))
            fast.confirm(fastSample, at: 0.6)
            // Simulate a checkpoint surviving without its replacement archive.
            store.saveRoute(fast, includeArchive: false)
            let interrupted = await store.load()
            let safe = try XCTUnwrap(interrupted.core)
            XCTAssertTrue(interrupted.damaged)
            XCTAssertEqual(safe.playbackID, slow.playbackID)
            XCTAssertNil(safe.confirmed)
            XCTAssertEqual(safe.snapshot.progress, 0)
            XCTAssertEqual(safe.snapshot.status, .paused)
            XCTAssertEqual(safe.plan?.cumulativeTime, slow.plan?.cumulativeTime)

            store.saveRoute(fast, includeArchive: true)
            let recovered = await store.load()
            XCTAssertFalse(recovered.damaged)
            XCTAssertEqual(recovered.core?.playbackID, fast.playbackID)
            XCTAssertEqual(recovered.core?.confirmed, fastSample)
            XCTAssertEqual(recovered.core?.plan?.cumulativeTime, fast.plan?.cumulativeTime)
        }
    }

    func testReopenAtSegmentBoundaryRequiresExplicitSelectionAndAcceptsUnconfirmedNextSegment() async throws {
        try await withStore { _, store in
            let track = self.track(segmentCount: 2)
            var original = RoutePlaybackCore(track: track, speed: 2, variation: { 1 })
            store.saveRoute(original, includeArchive: true)
            original.start(at: 0)
            original.confirm(try XCTUnwrap(original.plan?.sample(at: 10_000)), at: 0.5)
            store.saveRoute(original, includeArchive: false)
            let waiting = await store.load()
            var boundary = try XCTUnwrap(waiting.core)
            XCTAssertFalse(waiting.damaged)
            XCTAssertEqual(boundary.snapshot.status, .awaitingNextSegment)
            XCTAssertEqual(boundary.snapshot.segmentIndex, 0)
            XCTAssertNil(boundary.proposedSample(at: 100_000))

            XCTAssertEqual(boundary.selectNextSegment(), track.segments[1].points.first)
            XCTAssertNil(boundary.confirmed)
            store.saveRoute(boundary, includeArchive: false)
            let selected = await store.load()
            var paused = try XCTUnwrap(selected.core)
            XCTAssertFalse(selected.damaged)
            XCTAssertEqual(paused.snapshot.status, .paused)
            XCTAssertEqual(paused.snapshot.segmentIndex, 1)
            XCTAssertGreaterThan(paused.snapshot.progress, 0)
            XCTAssertNil(paused.confirmed)
            XCTAssertNil(paused.proposedSample(at: 100_000))

            // A second launch must accept the paused, unconfirmed state too.
            store.saveRoute(paused, includeArchive: false)
            let secondLaunch = await store.load()
            XCTAssertFalse(secondLaunch.damaged)
            XCTAssertEqual(secondLaunch.core?.snapshot, paused.snapshot)
            paused.start(at: 100_000)
            XCTAssertEqual(paused.proposedSample(at: 100_000)?.point, track.segments[1].points.first)
        }
    }

    func testCompletedRouteStaysCompletedAndNeverRestartsItself() async throws {
        try await withStore { _, store in
            var original = RoutePlaybackCore(track: self.track(), speed: 2, variation: { 1 })
            original.start(at: 0)
            original.confirm(try XCTUnwrap(original.plan?.sample(at: 10_000)), at: 0.5)
            store.saveRoute(original, includeArchive: true)
            let loaded = await store.load()
            var restored = try XCTUnwrap(loaded.core)
            XCTAssertFalse(loaded.damaged)
            XCTAssertEqual(restored.snapshot.status, .completed)
            XCTAssertEqual(restored.confirmed, original.confirmed)
            XCTAssertEqual(restored.snapshot.progress, 1)
            XCTAssertNil(restored.proposedSample(at: 100_000))
            XCTAssertNil(restored.selectNextSegment())
        }
    }

    func testInvalidCheckpointResetsProgressOnOriginalTimingPlanAndPreservesSource() async throws {
        try await withStore { defaults, store in
            var original = RoutePlaybackCore(track: self.track(), speed: 7, variation: { 1.07 })
            store.saveRoute(original, includeArchive: true)
            original.start(at: 0)
            original.confirm(try XCTUnwrap(original.proposedSample(at: 0.5)), at: 0.6)
            store.saveRoute(original, includeArchive: false)
            await store.flush()
            let checkpoint = try XCTUnwrap(defaults.data(forKey: self.checkpointKey))
            for damage in ["negativeElapsed", "futureElapsed", "invalidCoordinate", "distance", "progress", "completedDistance", "completedTooEarly", "nilConfirmed", "wrongSegment", "wrongTotal"] {
                defaults.set(checkpoint, forKey: self.checkpointKey)
                try self.mutate(self.checkpointKey, defaults: defaults) { object in
                    var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
                    var sample = try XCTUnwrap(object["confirmed"] as? [String: Any])
                    switch damage {
                    case "negativeElapsed": sample["elapsed"] = -1
                    case "futureElapsed": sample["elapsed"] = 1_000_000
                    case "invalidCoordinate": sample["point"] = ["latitude": 91, "longitude": 0]
                    case "distance": sample["distance"] = 999
                    case "progress": snapshot["progress"] = 0.99
                    case "completedDistance": snapshot["completedDistance"] = 999
                    case "completedTooEarly": snapshot["status"] = "completed"
                    case "wrongSegment": snapshot["segmentIndex"] = 999
                    case "wrongTotal": snapshot["totalDistance"] = 999
                    default: break
                    }
                    object["snapshot"] = snapshot
                    object["confirmed"] = damage == "nilConfirmed" ? NSNull() : sample
                }
                let raw = defaults.data(forKey: self.checkpointKey)
                let loaded = await store.load()
                XCTAssertTrue(loaded.damaged, damage)
                XCTAssertEqual(loaded.core?.snapshot.status, .paused, damage)
                XCTAssertEqual(loaded.core?.snapshot.progress, 0, damage)
                XCTAssertNil(loaded.core?.confirmed, damage)
                XCTAssertEqual(loaded.core?.plan?.cumulativeTime, original.plan?.cumulativeTime, damage)
                XCTAssertEqual(defaults.data(forKey: self.checkpointKey), raw, damage)
            }
        }
    }

    func testInvalidArchiveGeometryTimingAndEmbeddedProgressAreRejected() async throws {
        try await withStore { defaults, store in
            let original = RoutePlaybackCore(track: self.track(), speed: 2, variation: { 1 })
            store.saveRoute(original, includeArchive: true)
            await store.flush()
            let archive = try XCTUnwrap(defaults.data(forKey: self.archiveKey))
            for damage in ["distance", "zeroTime", "nonzeroOrigin", "wrongPoint", "badProgress", "wrongTotal"] {
                defaults.set(archive, forKey: self.archiveKey)
                try self.mutate(self.archiveKey, defaults: defaults) { object in
                    var core = try XCTUnwrap(object["core"] as? [String: Any])
                    var plans = try XCTUnwrap(core["plans"] as? [[String: Any]])
                    var snapshot = try XCTUnwrap(core["snapshot"] as? [String: Any])
                    switch damage {
                    case "distance": plans[0]["cumulativeDistance"] = [0, 999]
                    case "zeroTime": plans[0]["cumulativeTime"] = [0, 0]
                    case "nonzeroOrigin": plans[0]["cumulativeTime"] = [1, 100]
                    case "wrongPoint": plans[0]["points"] = [["latitude": 0, "longitude": 1], ["latitude": 0, "longitude": 2]]
                    case "badProgress": snapshot["progress"] = 0.5
                    case "wrongTotal": snapshot["totalDistance"] = 999
                    default: break
                    }
                    core["plans"] = plans
                    core["snapshot"] = snapshot
                    object["core"] = core
                }
                let raw = defaults.data(forKey: self.archiveKey)
                let loaded = await store.load()
                XCTAssertTrue(loaded.damaged, damage)
                XCTAssertNil(loaded.core, damage)
                XCTAssertEqual(defaults.data(forKey: self.archiveKey), raw, damage)
            }
        }
    }

    func testFutureVersionsAndUnexpectedPreferenceTypesAreReportedWithoutRewritingData() async throws {
        try await withStore { defaults, store in
            let original = RoutePlaybackCore(track: self.track(), speed: 2, variation: { 1 })
            for key in [self.draftKey, self.archiveKey, self.checkpointKey] {
                for futureVersion in [false, true] {
                    store.saveDraft(original.track)
                    store.saveRoute(original, includeArchive: true)
                    await store.flush()
                    if futureVersion {
                        try self.mutate(key, defaults: defaults) { $0["version"] = 99 }
                    } else { defaults.set("unexpected preference type", forKey: key) }
                    let raw = defaults.object(forKey: key) as? NSObject
                    let loaded = await store.load()
                    XCTAssertTrue(loaded.damaged, key)
                    XCTAssertEqual(defaults.object(forKey: key) as? NSObject, raw, key)
                    if key == self.draftKey { XCTAssertNil(loaded.draft) }
                    if key == self.archiveKey { XCTAssertNil(loaded.core) }
                    if key == self.checkpointKey {
                        XCTAssertEqual(loaded.core?.snapshot.status, .paused)
                        XCTAssertNil(loaded.core?.confirmed)
                    }
                }
            }
        }
    }

    func testMissingAndOrphanedCheckpointCannotAuthorizeMovement() async throws {
        try await withStore { defaults, store in
            let original = RoutePlaybackCore(track: self.track(), speed: 3, variation: { 1 })
            store.saveRoute(original, includeArchive: true)
            await store.flush()
            let checkpoint = defaults.data(forKey: self.checkpointKey)
            defaults.removeObject(forKey: self.checkpointKey)
            let missing = await store.load()
            XCTAssertTrue(missing.damaged)
            XCTAssertEqual(missing.core?.snapshot.status, .paused)
            XCTAssertEqual(missing.core?.plan?.cumulativeTime, original.plan?.cumulativeTime)
            defaults.removeObject(forKey: self.archiveKey)
            defaults.set(checkpoint, forKey: self.checkpointKey)
            let orphaned = await store.load()
            XCTAssertTrue(orphaned.damaged)
            XCTAssertNil(orphaned.core)
        }
    }

    func testDraftLimitsAndDuplicateSegmentIdentitiesDoNotOverwriteSavedDraft() async throws {
        try await withStore { _, store in
            let points = Array(repeating: RoutePoint(latitude: 0, longitude: 0), count: 50_000)
            let valid = RouteTrack(name: "Maximum", segments: [RouteSegment(points: points)])
            store.saveDraft(valid)
            let loaded = await store.load()
            XCTAssertFalse(loaded.damaged)
            XCTAssertEqual(loaded.draft?.segments.first?.points.count, 50_000)
            let oversized = RouteTrack(name: "Too many", segments: [RouteSegment(points: points + [points[0]])])
            store.saveDraft(oversized)
            let repeated = self.track().segments[0]
            store.saveDraft(RouteTrack(name: "Duplicate identities", segments: [repeated, repeated]))
            let afterInvalidWrites = await store.load()
            XCTAssertEqual(afterInvalidWrites.draft, valid)
            store.saveDraft(nil)
            let cleared = await store.load()
            XCTAssertNil(cleared.draft)
            XCTAssertFalse(cleared.damaged)
        }
    }

    func testZeroDistanceSegmentsRoundTripBeforeAndAfterExplicitSegmentSelection() async throws {
        try await withStore { _, store in
            let point = RoutePoint(latitude: 0, longitude: 0)
            var core = RoutePlaybackCore(track: RouteTrack(name: "Duplicates", segments: [RouteSegment(points: [point, point]), RouteSegment(points: [point, point])]), speed: 2, variation: { 1 })
            core.start(at: 0)
            core.confirm(try XCTUnwrap(core.plan?.sample(at: 0)), at: 0.5)
            store.saveRoute(core, includeArchive: true)
            let first = await store.load()
            XCTAssertFalse(first.damaged)
            XCTAssertEqual(first.core?.snapshot.status, .awaitingNextSegment)
            XCTAssertNotNil(core.selectNextSegment())
            store.saveRoute(core, includeArchive: false)
            let second = await store.load()
            XCTAssertFalse(second.damaged)
            XCTAssertEqual(second.core?.snapshot.status, .paused)
            XCTAssertEqual(second.core?.snapshot.segmentIndex, 1)
        }
    }

    private func track(segmentCount: Int = 1) -> RouteTrack {
        let segments = (0..<segmentCount).map { index in
            RouteSegment(points: [RoutePoint(latitude: 0, longitude: Double(index) * 10),
                                  RoutePoint(latitude: 0, longitude: Double(index) * 10 + 0.001)])
        }
        return RouteTrack(name: "Workspace test", segments: segments)
    }

    private func mutate(_ key: String, defaults: UserDefaults, body: (inout [String: Any]) throws -> Void) throws {
        let data = try XCTUnwrap(defaults.data(forKey: key))
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        try body(&object)
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
    }

    private func withStore(_ body: (UserDefaults, RouteWorkspaceStore) async throws -> Void) async throws {
        let suite = "LocationRouteWorkspaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RouteWorkspaceStore(defaults: defaults)
        do { try await body(defaults, store) }
        catch { await store.flush(); throw error }
        await store.flush()
    }
}
