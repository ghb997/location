import CoreLocation
import Foundation

enum GPXError: LocalizedError {
    case malformed, noPoints, invalidCoordinate, tooLarge, selectionRequired

    var errorDescription: String? {
        switch self {
        case .malformed: return L10n.tr("The GPX file is not valid XML.")
        case .noPoints: return L10n.tr("No track points found in GPX")
        case .invalidCoordinate: return L10n.tr("The GPX file contains invalid coordinates.")
        case .tooLarge: return L10n.tr("The GPX file is too large. Use at most 10 MB and 50,000 points.")
        case .selectionRequired: return L10n.tr("This GPX contains multiple tracks or segments. Choose one in the route planner.")
        }
    }
}

enum GPXCodec {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumPoints = 50_000

    static func parseDocument(_ url: URL, byteLimit: Int = maximumBytes, pointLimit: Int = maximumPoints) throws -> RouteDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = min(maximumBytes, max(0, byteLimit))
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        return try parseDocument(data: data, byteLimit: limit, pointLimit: pointLimit)
    }

    static func parseDocument(data: Data, byteLimit: Int = maximumBytes, pointLimit: Int = maximumPoints) throws -> RouteDocument {
        try Task.checkCancellation()
        guard data.count <= min(maximumBytes, max(0, byteLimit)) else { throw GPXError.tooLarge }
        let reader = GPXReader(pointLimit: min(maximumPoints, max(0, pointLimit)))
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse()
        try Task.checkCancellation()
        if let error = reader.error { throw error }
        guard parsed, reader.isGPX else { throw GPXError.malformed }
        var tracks = reader.tracks
        if !reader.waypoints.isEmpty {
            tracks.append(RouteTrack(name: L10n.tr("Waypoint route"), kind: .waypoints,
                                     segments: [RouteSegment(points: reader.waypoints)]))
        }
        let document = RouteDocument(tracks: tracks)
        guard document.preferredTrack != nil else { throw GPXError.noPoints }
        return document
    }

    /// Array callers must not accidentally join independent GPX segments.
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        try legacyCoordinates(from: parseDocument(url))
    }

    static func parse(data: Data) throws -> [CLLocationCoordinate2D] {
        try legacyCoordinates(from: parseDocument(data: data))
    }

    private static func legacyCoordinates(from document: RouteDocument) throws -> [CLLocationCoordinate2D] {
        guard let preferred = document.preferredTrack else { throw GPXError.noPoints }
        let candidates = document.tracks.filter { $0.kind == preferred.kind && !$0.segments.allSatisfy { $0.points.isEmpty } }
        let segments = preferred.segments.filter { !$0.points.isEmpty }
        guard candidates.count == 1, segments.count == 1 else { throw GPXError.selectionRequired }
        return segments[0].coordinates
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = L10n.tr("Locus Route")) -> String {
        export(RouteTrack(name: name, coordinates: coordinates))
    }

    static func export(_ track: RouteTrack) -> String {
        let name = escape(track.name)
        let body: String
        switch track.kind {
        case .route:
            if track.segments.count > 1 {
                var segmentedTrack = track
                segmentedTrack.kind = .track
                return export(segmentedTrack)
            }
            let points = track.segments.flatMap(\.points).filter { RouteGeometry.isValid($0.coordinate) }
            body = "  <rte><name>\(name)</name>\n" + points.map { element("rtept", point: $0) }.joined(separator: "\n") + "\n  </rte>"
        case .waypoints:
            body = track.segments.flatMap(\.points).filter { RouteGeometry.isValid($0.coordinate) }.map { element("wpt", point: $0) }.joined(separator: "\n")
        case .track:
            let segments = track.segments.map { segment in
                "    <trkseg>\n" + segment.points.filter { RouteGeometry.isValid($0.coordinate) }.map { element("trkpt", point: $0) }.joined(separator: "\n") + "\n    </trkseg>"
            }.joined(separator: "\n")
            body = "  <trk><name>\(name)</name>\n\(segments)\n  </trk>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
        \(body)
        </gpx>
        """
    }

    private static func element(_ tag: String, point: RoutePoint) -> String {
        String(format: "      <%@ lat=\"%.8f\" lon=\"%.8f\"/>", locale: Locale(identifier: "en_US_POSIX"), tag, point.latitude, point.longitude)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var tracks: [RouteTrack] = []
    var waypoints: [RoutePoint] = []
    var error: Error?
    var isGPX = false
    private let pointLimit: Int
    private var stack: [String] = []
    private var count = 0
    private var activeTrack: Int?
    private var activeSegment: Int?
    private var nameText = ""
    private var readingName = false
    private var rootPointTracks: [String: Int] = [:]

    init(pointLimit: Int) { self.pointLimit = pointLimit }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if Task.isCancelled { error = CancellationError(); parser.abortParsing(); return }
        let parent = stack.last
        stack.append(elementName)
        if stack.count == 1 { isGPX = elementName == "gpx" }
        guard isGPX else { return }
        if (elementName == "trk" || elementName == "rte") && parent == "gpx" {
            let kind: RouteTrack.Kind = elementName == "trk" ? .track : .route
            tracks.append(RouteTrack(name: L10n.format("Track %d", tracks.count + 1), kind: kind, segments: kind == .route ? [RouteSegment(points: [])] : []))
            activeTrack = tracks.count - 1
            activeSegment = kind == .route ? 0 : nil
        } else if stack == ["gpx", "trk", "trkseg"], let index = activeTrack {
            tracks[index].segments.append(RouteSegment(points: []))
            activeSegment = tracks[index].segments.count - 1
        } else if (stack == ["gpx", "trk", "name"] || stack == ["gpx", "rte", "name"]), activeTrack != nil {
            readingName = true
            nameText = ""
        }
        guard ["trkpt", "rtept", "wpt"].contains(elementName) else { return }
        guard stack == ["gpx", "trk", "trkseg", "trkpt"] || stack == ["gpx", "rte", "rtept"] ||
              (stack.count == 2 && parent == "gpx") else { return }
        guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init),
              RouteGeometry.isValid(.init(latitude: lat, longitude: lon)) else {
            error = GPXError.invalidCoordinate
            parser.abortParsing()
            return
        }
        count += 1
        guard count <= pointLimit else { error = GPXError.tooLarge; parser.abortParsing(); return }
        let point = RoutePoint(latitude: lat, longitude: lon)
        if elementName == "wpt", parent == "gpx" {
            waypoints.append(point)
        } else if elementName == "trkpt", parent == "trkseg", let track = activeTrack, let segment = activeSegment {
            tracks[track].segments[segment].points.append(point)
        } else if elementName == "rtept", parent == "rte", let track = activeTrack {
            tracks[track].segments[0].points.append(point)
        } else if parent == "gpx" {
            // Retain existing simple root-point compatibility.
            let kind: RouteTrack.Kind = elementName == "trkpt" ? .track : .route
            if let index = rootPointTracks[elementName] {
                tracks[index].segments[0].points.append(point)
            } else {
                rootPointTracks[elementName] = tracks.count
                tracks.append(RouteTrack(name: L10n.format("Track %d", tracks.count + 1), kind: kind, segments: [RouteSegment(points: [point])]))
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingName { nameText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if (stack == ["gpx", "trk", "name"] || stack == ["gpx", "rte", "name"]), readingName, let index = activeTrack {
            let value = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { tracks[index].name = value }
            readingName = false
        }
        if stack == ["gpx", "trk", "trkseg"] { activeSegment = nil }
        if stack == ["gpx", "trk"] || stack == ["gpx", "rte"] { activeTrack = nil; activeSegment = nil }
        if !stack.isEmpty { stack.removeLast() }
    }
}
