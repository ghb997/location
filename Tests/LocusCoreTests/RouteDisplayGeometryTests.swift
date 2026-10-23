import CoreLocation
import XCTest
@testable import LocusCore

final class RouteDisplayGeometryTests: XCTestCase {
    func testFiftyThousandPointsAreProjectedOnceAndSourceIsUnchanged() throws {
        let points = (0..<50_000).map { index in
            RoutePoint(latitude: 30 + Double(index) * 0.000001, longitude: 120 + Double(index) * 0.000001)
        }
        let track = RouteTrack(name: "Large GPX", segments: [RouteSegment(points: points)])
        let original = track
        var projectedCount = 0
        let prepared = try RouteDisplayGeometry(track: track) { coordinate in
            projectedCount += 1
            return CLLocationCoordinate2D(latitude: coordinate.latitude + 0.001, longitude: coordinate.longitude + 0.002)
        }

        XCTAssertEqual(projectedCount, 50_000)
        XCTAssertEqual(prepared.segments.count, 1)
        XCTAssertEqual(prepared.segments.first?.coordinates.count, 50_000)
        XCTAssertEqual(track, original)
        XCTAssertEqual(prepared.segments[0].coordinates[0].latitude, points[0].latitude + 0.001, accuracy: 0.000000001)
        XCTAssertEqual(prepared.segments[0].coordinates[49_999].longitude, points[49_999].longitude + 0.002, accuracy: 0.000000001)
        // Repeated UI reads use prepared arrays/distances, never the projector.
        for _ in 0..<10 {
            _ = prepared.segments[0].coordinates.count
            _ = prepared.remainingDistances[0]
        }
        XCTAssertEqual(projectedCount, 50_000)
    }

    func testSegmentsStaySeparateAndSuffixDistancesExcludeIntersegmentGap() throws {
        let first = RouteSegment(points: [RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: 0.01)])
        let empty = RouteSegment(points: [])
        let last = RouteSegment(points: [RoutePoint(latitude: 40, longitude: 100), RoutePoint(latitude: 40, longitude: 100.02)])
        let track = RouteTrack(name: "Separate segments", segments: [first, empty, last])
        let prepared = try RouteDisplayGeometry(track: track) { coordinate in
            // Display projection must not change distances measured in WGS-84.
            CLLocationCoordinate2D(latitude: coordinate.latitude + 1, longitude: coordinate.longitude + 1)
        }

        XCTAssertEqual(prepared.segments.map(\.id), [first.id, empty.id, last.id])
        XCTAssertEqual(prepared.segments.map { $0.coordinates.count }, [2, 0, 2])
        XCTAssertEqual(prepared.remainingDistances.count, 3)
        XCTAssertEqual(prepared.remainingDistances[0], first.distance + last.distance, accuracy: 0.001)
        XCTAssertEqual(prepared.remainingDistances[1], last.distance, accuracy: 0.001)
        XCTAssertEqual(prepared.remainingDistances[2], last.distance, accuracy: 0.001)
        let gap = RouteGeometry.distance(from: first.points.last!.coordinate, to: last.points.first!.coordinate)
        XCTAssertGreaterThan(gap, prepared.remainingDistances[0] * 100)
    }

    func testProjectionFailureDoesNotReturnPartialGeometryOrChangeOriginal() {
        enum ProjectionError: Error { case unavailable }
        let track = RouteTrack(name: "Original", segments: [RouteSegment(points: [
            RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 1, longitude: 1)
        ])])
        let original = track
        var count = 0
        XCTAssertThrowsError(try RouteDisplayGeometry(track: track) { coordinate in
            count += 1
            if count == 2 { throw ProjectionError.unavailable }
            return coordinate
        })
        XCTAssertEqual(count, 2)
        XCTAssertEqual(track, original)
    }
}
