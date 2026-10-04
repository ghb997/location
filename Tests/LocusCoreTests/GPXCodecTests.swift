import CoreLocation
import XCTest
@testable import LocusCore

final class GPXCodecTests: XCTestCase {
    func testMixedAttributeOrderAndQuotesPreserveAllPoints() throws {
        let data = Data("<gpx><trk><trkseg><trkpt lat='31.2' lon='121.5'/><trkpt lon=\"121.6\" lat=\"31.3\"/></trkseg></trk></gpx>".utf8)
        let points = try GPXCodec.parse(data: data)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].latitude, 31.3)
        XCTAssertEqual(points[1].longitude, 121.6)
    }

    func testNamespacedRouteAndTrackPriority() throws {
        let data = Data("<g:gpx xmlns:g='http://www.topografix.com/GPX/1/1'><g:wpt lat='10' lon='20'/><g:trk><g:trkseg><g:trkpt lat='30' lon='40'/></g:trkseg></g:trk></g:gpx>".utf8)
        let points = try GPXCodec.parse(data: data)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].latitude, 30)
    }

    func testRoutePointsAndWaypointFallback() throws {
        let route = try GPXCodec.parse(data: Data("<gpx><rte><rtept lon='20' lat='10'/></rte></gpx>".utf8))
        let waypoint = try GPXCodec.parse(data: Data("<gpx><wpt lat='11' lon='21'/></gpx>".utf8))
        XCTAssertEqual(route[0].longitude, 20)
        XCTAssertEqual(waypoint[0].latitude, 11)
    }

    func testMalformedAndNonGPXXMLAreRejected() {
        for xml in ["<gpx><trkpt lat='1' lon='2'/>", "<other lat='1' lon='2'/>", "<gpx/>"] {
            XCTAssertThrowsError(try GPXCodec.parse(data: Data(xml.utf8)))
        }
    }

    func testInvalidCoordinateIsNotSilentlyDropped() {
        for latitude in ["91", "nan", "inf", "no", ""] {
            let xml = "<gpx><trkpt lat='1' lon='2'/><trkpt lat='\(latitude)' lon='2'/></gpx>"
            XCTAssertThrowsError(try GPXCodec.parse(data: Data(xml.utf8)))
        }
        XCTAssertThrowsError(try GPXCodec.parse(data: Data("<gpx><wpt lat='1' lon='181'/></gpx>".utf8)))
    }

    func testExportEscapesXMLAndRoundTripsCoordinates() throws {
        let original = [CLLocationCoordinate2D(latitude: 31.2345678, longitude: 121.456789)]
        let xml = GPXCodec.export(original, name: "浦东 <A> & \"B\" 'C'")
        XCTAssertTrue(xml.contains("&lt;A&gt; &amp; &quot;B&quot; &apos;C&apos;"))
        let decoded = try GPXCodec.parse(data: Data(xml.utf8))
        XCTAssertEqual(decoded[0].latitude, original[0].latitude, accuracy: 0.00000001)
        XCTAssertEqual(decoded[0].longitude, original[0].longitude, accuracy: 0.00000001)
    }

    func testInputLimits() {
        XCTAssertThrowsError(try GPXCodec.parse(data: Data(count: GPXCodec.maximumBytes + 1)))
        let xml = "<gpx>" + String(repeating: "<wpt lat='1' lon='2'/>", count: GPXCodec.maximumPoints + 1) + "</gpx>"
        XCTAssertThrowsError(try GPXCodec.parse(data: Data(xml.utf8)))
    }
}
