import CoreLocation
import XCTest
@testable import LocusCore

final class MapViewportGeometryTests: XCTestCase {
    func testPointLandsBetweenActualOverlays() throws {
        let point = MapViewportGeometry.point(.init(latitude: 31.23, longitude: 121.47))
        let frame = try XCTUnwrap(MapViewportGeometry.fit(point, width: 390, height: 760, top: 180, bottom: 330))
        XCTAssertEqual((point.x + point.width / 2 - frame.x) / frame.width * 390, 195, accuracy: 0.001)
        XCTAssertEqual((point.y + point.height / 2 - frame.y) / frame.height * 760, 305, accuracy: 0.001)
    }

    func testFullRouteFitsInVisibleRegionInPortraitAndLandscape() throws {
        let route = try XCTUnwrap(MapViewportGeometry.bounds([
            .init(latitude: 31.2, longitude: 121.4), .init(latitude: 31.4, longitude: 121.8)]))
        for (w, h, top, bottom) in [(390.0, 760.0, 180.0, 330.0), (760, 300, 90, 130)] {
            let frame = try XCTUnwrap(MapViewportGeometry.fit(route, width: w, height: h, top: top, bottom: bottom))
            let minX = (route.x - frame.x) / frame.width * w
            let maxX = (route.x + route.width - frame.x) / frame.width * w
            let minY = (route.y - frame.y) / frame.height * h
            let maxY = (route.y + route.height - frame.y) / frame.height * h
            XCTAssertGreaterThanOrEqual(minX, 16)
            XCTAssertLessThanOrEqual(maxX, w - 16)
            XCTAssertGreaterThanOrEqual(minY, top)
            XCTAssertLessThanOrEqual(maxY, h - bottom)
        }
    }

    func testKeyboardHeightAndAsymmetricPanelsShiftContent() throws {
        let point = MapViewportGeometry.point(.init(latitude: 35, longitude: 139))
        let frame = try XCTUnwrap(MapViewportGeometry.fit(point, width: 500, height: 320,
            top: 100, bottom: 140, left: 100, right: 20))
        XCTAssertEqual((point.x + point.width / 2 - frame.x) / frame.width * 500, 290, accuracy: 0.001)
        XCTAssertEqual((point.y + point.height / 2 - frame.y) / frame.height * 320, 140, accuracy: 0.001)
    }

    func testAntimeridianRouteUsesShortArc() throws {
        let bounds = try XCTUnwrap(MapViewportGeometry.bounds([
            .init(latitude: 10, longitude: 179), .init(latitude: 11, longitude: -179)]))
        XCTAssertEqual(bounds.width, 2 / 360, accuracy: 0.000001)
        XCTAssertGreaterThan(bounds.x + bounds.width, 1)
        let frame = try XCTUnwrap(MapViewportGeometry.fit(bounds, width: 800, height: 600, top: 130, bottom: 220))
        XCTAssertLessThan(frame.width, 0.1)
    }

    func testDegenerateTrackAndPolarLocationProduceFiniteNonzeroBounds() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 90, longitude: -180)
        let bounds = try XCTUnwrap(MapViewportGeometry.bounds([coordinate, coordinate]))
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        let frame = try XCTUnwrap(MapViewportGeometry.fit(bounds, width: 500, height: 800, top: 100, bottom: 300))
        XCTAssertTrue(frame.y.isFinite)
        XCTAssertTrue(frame.height.isFinite)
    }

    func testImpossibleOrInvalidViewportDoesNotMoveCamera() {
        let point = MapViewportGeometry.point(.init(latitude: 0, longitude: 0))
        XCTAssertNil(MapViewportGeometry.fit(point, width: 390, height: 100, top: 80, bottom: 80))
        XCTAssertNil(MapViewportGeometry.fit(point, width: .nan, height: 800, top: 0, bottom: 0))
        XCTAssertNil(MapViewportGeometry.bounds([]))
        XCTAssertNil(MapViewportGeometry.bounds([.init(latitude: 999, longitude: 0)]))
    }
}
