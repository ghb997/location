import CoreLocation
import XCTest
@testable import LocusCore

final class GeometryAndPairingTests: XCTestCase {
    func testDateLineInterpolationTakesShortArc() {
        let start = CLLocationCoordinate2D(latitude: 10, longitude: 179)
        let end = CLLocationCoordinate2D(latitude: 12, longitude: -179)
        let midpoint = RouteGeometry.interpolate(from: start, to: end, fraction: 0.5)
        XCTAssertEqual(midpoint.latitude, 11)
        XCTAssertEqual(abs(midpoint.longitude), 180)
    }

    func testRouteTimingUsesActualSegmentDistance() {
        // A 1 m final segment at 2 m/s takes 0.5 seconds, not the nominal 4 m step / speed.
        XCTAssertEqual(RouteGeometry.stepDelay(distance: 1, steps: 1, speed: 2), 0.5)
        XCTAssertEqual(RouteGeometry.stepDelay(distance: 10, steps: 3, speed: 2) * 3, 5)
        XCTAssertEqual(RouteGeometry.stepDelay(distance: 10, steps: 0, speed: 2), 0)
    }

    func testSamplingBoundsAllocationAndRejectsInvalidInput() {
        let points = [CLLocationCoordinate2D(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 170)]
        XCTAssertEqual(RouteGeometry.sample(points, every: 1).count, 2)
        XCTAssertTrue(RouteGeometry.sample(points, every: 0).isEmpty)
        XCTAssertTrue(RouteGeometry.sample(points, every: .nan).isEmpty)
        XCTAssertTrue(RouteGeometry.sample([.init(latitude: .nan, longitude: 0)], every: 10).isEmpty)
    }

    func testSamplingPreservesEndpoints() {
        let points = [CLLocationCoordinate2D(latitude: 31, longitude: 121), .init(latitude: 31.001, longitude: 121.001)]
        let result = RouteGeometry.sample(points, every: 10)
        XCTAssertGreaterThan(result.count, 2)
        XCTAssertEqual(result.first!.latitude, points[0].latitude)
        XCTAssertEqual(result.last!.longitude, points[1].longitude, accuracy: 0.000001)
    }

    func testIPv4Validation() {
        for value in ["10.7.0.1", "127.0.0.1", "192.168.1.254"] { XCTAssertTrue(TunnelConfig.isValidIP(value)) }
        for value in ["", "10.7.0", "256.7.0.1", "10..0.1", "10.7.0.1:42", "::1", "01.2.3.4", " 10.7.0.1", "1e1.7.0.1"] {
            XCTAssertFalse(TunnelConfig.isValidIP(value), value)
        }
    }

    func testPairingAcceptsXMLAndBinary() throws {
        let valid: [String: Any] = ["public_key": Data(repeating: 1, count: 32), "private_key": Data(repeating: 2, count: 32), "identifier": "test-host", "alt_irk": Data(count: 16)]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: valid, format: format, options: 0)
            XCTAssertTrue(PairingFileValidator.isValid(data))
        }
    }

    func testPairingRejectsLockdownAndMalformedData() throws {
        XCTAssertFalse(PairingFileValidator.isValid(Data("<?xml version='1.0'?><plist>broken".utf8)))
        for dictionary: [String: Any] in [
            ["HostID": "lockdown", "SystemBUID": "unsupported"],
            ["public_key": Data(count: 31), "private_key": Data(count: 32), "identifier": "x"],
            ["public_key": Data(count: 32), "private_key": Data(count: 32), "identifier": " "],
            ["public_key": Data(count: 32), "private_key": Data(count: 32), "identifier": "x", "alt_irk": Data(count: 1)]
        ] {
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
            XCTAssertFalse(PairingFileValidator.isValid(data))
        }
    }
}
