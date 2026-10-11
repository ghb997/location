import CoreLocation
import XCTest
@testable import LocusCore

final class RoutePlaybackTests: XCTestCase {
    private func segment(_ longitude: Double = 0, meters: Double = 10) -> RouteSegment {
        RouteSegment(points: [RoutePoint(latitude: 0, longitude: longitude),
                              RoutePoint(latitude: 0, longitude: longitude + meters / 111_319.49079327357)])
    }

    func testTimingIncludesTransportElapsedWithoutCompoundingDelay() throws {
        let track = RouteTrack(name: "Test", segments: [segment(meters: 100)])
        var core = RoutePlaybackCore(track: track, speed: 2, variation: { 1 })
        core.start(at: 100)
        let first = try XCTUnwrap(core.proposedSample(at: 100.5))
        core.confirm(first, at: 100.8, writeStartedAt: 100.5)
        XCTAssertEqual(core.nextDeadline(after: 100.8), 101, accuracy: 1e-9)
        let second = try XCTUnwrap(core.proposedSample(at: 101))
        XCTAssertEqual(second.elapsed, 1, accuracy: 1e-9)
        XCTAssertEqual(second.distance, 2, accuracy: 0.03)
        XCTAssertEqual(core.snapshot.completedDistance, first.distance, accuracy: 1e-9)
    }

    func testPauseDuringWriteCommitsLastAcknowledgedPoint() throws {
        var core = RoutePlaybackCore(track: RouteTrack(name: "Test", segments: [segment(meters: 100)]), speed: 2, variation: { 1 })
        core.start(at: 0)
        let pending = try XCTUnwrap(core.proposedSample(at: 0.5))
        core.requestPause()
        XCTAssertEqual(core.snapshot.status, .pausing)
        core.confirm(pending, at: 0.9, writeStartedAt: 0.5)
        XCTAssertEqual(core.snapshot.status, .paused)
        XCTAssertEqual(core.snapshot.pauseReason, .user)
        XCTAssertEqual(core.confirmed, pending)
        XCTAssertNil(core.proposedSample(at: 10))
        core.start(at: 10)
        let resumed = try XCTUnwrap(core.proposedSample(at: 10.5))
        XCTAssertEqual(resumed.elapsed, 1, accuracy: 1e-9)
    }

    func testSuspensionFreezesUntilUserResumes() throws {
        var core = RoutePlaybackCore(track: RouteTrack(name: "Test", segments: [segment(meters: 100)]), speed: 2, variation: { 1 })
        core.start(at: 0)
        let initial = try XCTUnwrap(core.plan?.sample(at: 0))
        core.confirm(initial, at: 0)
        XCTAssertNil(core.proposedSample(at: 3))
        XCTAssertEqual(core.snapshot.status, .paused)
        XCTAssertEqual(core.snapshot.pauseReason, .executionInterrupted)
        XCTAssertEqual(core.confirmed, initial)
        core.start(at: 30)
        XCTAssertEqual(try XCTUnwrap(core.proposedSample(at: 30.5)).elapsed, 0.5, accuracy: 1e-9)
    }

    func testLongNativeWritePausesAfterConfirmingItsResult() throws {
        var core = RoutePlaybackCore(track: RouteTrack(name: "Test", segments: [segment(meters: 100)]), speed: 2, variation: { 1 })
        core.start(at: 0)
        let pending = try XCTUnwrap(core.proposedSample(at: 0.5))
        core.confirm(pending, at: 3, writeStartedAt: 0.5)
        XCTAssertEqual(core.confirmed, pending)
        XCTAssertEqual(core.snapshot.pauseReason, .executionInterrupted)
    }

    func testDisconnectedRouteStaysPausedAfterStaticRecovery() throws {
        var core = RoutePlaybackCore(track: RouteTrack(name: "Test", segments: [segment(meters: 100)]), speed: 2, variation: { 1 })
        core.start(at: 0)
        let last = try XCTUnwrap(core.proposedSample(at: 0.5))
        core.confirm(last, at: 0.6)
        core.pause(.transportInterrupted)
        // A successful static heartbeat does not call start or mutate the route.
        core.confirm(last, at: 12)
        XCTAssertEqual(core.snapshot.status, .paused)
        XCTAssertEqual(core.confirmed, last)
        XCTAssertNil(core.proposedSample(at: 12.5))
    }

    func testSegmentsRequireExplicitSwitchAndExcludeGapDistance() throws {
        let first = segment(meters: 10)
        let second = segment(100, meters: 10)
        var core = RoutePlaybackCore(track: RouteTrack(name: "Two segments", segments: [first, second]), speed: 2, variation: { 1 })
        core.start(at: 0)
        let finish = try XCTUnwrap(core.plan?.sample(at: 100))
        core.confirm(finish, at: 0.5)
        XCTAssertEqual(core.snapshot.status, .awaitingNextSegment)
        XCTAssertEqual(core.snapshot.segmentIndex, 0)
        XCTAssertEqual(core.snapshot.totalDistance, 20, accuracy: 0.1)
        XCTAssertNil(core.proposedSample(at: 1))
        XCTAssertEqual(core.selectNextSegment(), second.points.first)
        XCTAssertEqual(core.snapshot.segmentIndex, 1)
        XCTAssertNil(core.confirmed)
        core.start(at: 1)
        let last = try XCTUnwrap(core.plan?.sample(at: 100))
        core.confirm(last, at: 1.5)
        XCTAssertEqual(core.snapshot.status, .completed)
        XCTAssertEqual(core.snapshot.progress, 1)
    }

    func testDateLineTimelineAndDuplicateEdges() throws {
        let points = [RoutePoint(latitude: 10, longitude: 179), RoutePoint(latitude: 10, longitude: 179),
                      RoutePoint(latitude: 10, longitude: -179)]
        let plan = RouteTimingPlan(segment: RouteSegment(points: points), speed: 10, variation: { 1 })
        let half = try XCTUnwrap(plan.sample(at: plan.duration / 2))
        XCTAssertEqual(abs(half.point.longitude), 180, accuracy: 1e-9)
        XCTAssertTrue(plan.sample(at: plan.duration)!.finished)
        XCTAssertEqual(plan.points.count, 3)
    }
}
