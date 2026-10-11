import XCTest
@testable import LocusCore

final class GPXDocumentTests: XCTestCase {
    func testMultipleTracksAndSegmentsKeepTheirNamesAndBoundaries() throws {
        let xml = """
        <gpx><trk><name>甲 &amp; 乙</name>
        <trkseg><trkpt lat='1' lon='2'/><trkpt lat='1' lon='2.001'/></trkseg>
        <trkseg><trkpt lat='40' lon='100'/><trkpt lat='40' lon='100.001'/></trkseg></trk>
        <trk><name>另一条</name><trkseg><trkpt lat='3' lon='4'/><trkpt lat='3' lon='4.001'/></trkseg></trk></gpx>
        """
        let document = try GPXCodec.parseDocument(data: Data(xml.utf8))
        XCTAssertEqual(document.tracks.count, 2)
        XCTAssertEqual(document.preferredTrack?.name, "甲 & 乙")
        XCTAssertEqual(document.tracks[0].segments.count, 2)
        XCTAssertEqual(document.tracks[0].segments[1].points[0].longitude, 100)
        XCTAssertThrowsError(try GPXCodec.parse(data: Data(xml.utf8))) { error in
            guard let gpxError = error as? GPXError, case .selectionRequired = gpxError else { return XCTFail("Expected explicit selection error") }
        }
        let roundTrip = try GPXCodec.parseDocument(data: Data(GPXCodec.export(document.tracks[0]).utf8))
        XCTAssertEqual(roundTrip.tracks.count, 1)
        XCTAssertEqual(roundTrip.tracks[0].name, document.tracks[0].name)
        XCTAssertEqual(roundTrip.tracks[0].segments.map(\.points), document.tracks[0].segments.map(\.points))
    }

    func testPointLimitIsSharedAcrossAllTracksAndWaypoints() {
        let data = Data("<gpx><trk><trkseg><trkpt lat='1' lon='2'/></trkseg></trk><rte><rtept lat='3' lon='4'/></rte><wpt lat='5' lon='6'/></gpx>".utf8)
        XCTAssertThrowsError(try GPXCodec.parseDocument(data: data, pointLimit: 2))
        XCTAssertThrowsError(try GPXCodec.parseDocument(data: data, byteLimit: 20))
        XCTAssertNoThrow(try GPXCodec.parseDocument(data: data, pointLimit: 3))
    }

    func testLegacyParserStillPrefersOneTrackOverUnrelatedWaypoints() throws {
        let data = Data("<gpx><wpt lat='5' lon='6'/><trk><trkseg><trkpt lat='1' lon='2'/><trkpt lat='1' lon='3'/></trkseg></trk></gpx>".utf8)
        let points = try GPXCodec.parse(data: data)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].latitude, 1)
    }

    func testNamespacedRoutesKeepTheRouteKind() throws {
        let data = Data("<g:gpx xmlns:g='http://www.topografix.com/GPX/1/1'><g:rte><g:name>路由</g:name><g:rtept lat='1' lon='2'/><g:rtept lat='2' lon='3'/></g:rte></g:gpx>".utf8)
        let track = try XCTUnwrap(GPXCodec.parseDocument(data: data).preferredTrack)
        XCTAssertEqual(track.kind, .route)
        XCTAssertEqual(track.name, "路由")
        XCTAssertTrue(GPXCodec.export(track).contains("<rte>"))
    }

    func testNestedExtensionRoutePointsCannotIndexAnActiveTrackSegment() throws {
        let data = Data("<gpx><trk><extensions><rte><rtept lat='90' lon='10'/></rte></extensions><trkseg><trkpt lat='1' lon='2'/><trkpt lat='2' lon='3'/></trkseg></trk></gpx>".utf8)
        let document = try GPXCodec.parseDocument(data: data)
        XCTAssertEqual(document.tracks.count, 1)
        XCTAssertEqual(document.tracks[0].segments.count, 1)
        XCTAssertEqual(document.tracks[0].segments[0].points.count, 2)
        XCTAssertEqual(document.tracks[0].segments[0].points[0].latitude, 1)
    }

    func testExportKeepsBoundariesWhenRouteContainsSeveralSegments() throws {
        let track = RouteTrack(name: "Separated route", kind: .route, segments: [
            RouteSegment(points: [RoutePoint(latitude: 1, longitude: 2), RoutePoint(latitude: 1, longitude: 3)]),
            RouteSegment(points: [RoutePoint(latitude: 40, longitude: 100), RoutePoint(latitude: 40, longitude: 101)])
        ])
        let document = try GPXCodec.parseDocument(data: Data(GPXCodec.export(track).utf8))
        XCTAssertEqual(document.tracks[0].kind, .track)
        XCTAssertEqual(document.tracks[0].segments.map(\.points), track.segments.map(\.points))
    }

    func testCancelledTaskDoesNotParseOrPublishDocument() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try GPXCodec.parseDocument(data: Data("<gpx><wpt lat='1' lon='2'/></gpx>".utf8))
        }
        do { _ = try await task.value; XCTFail("Cancelled parse returned a document") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
