import CoreLocation
import Foundation

enum GPXError: LocalizedError {
    case malformed, noPoints, invalidCoordinate, tooLarge

    var errorDescription: String? {
        switch self {
        case .malformed: return L10n.tr("The GPX file is not valid XML.")
        case .noPoints: return L10n.tr("No track points found in GPX")
        case .invalidCoordinate: return L10n.tr("The GPX file contains invalid coordinates.")
        case .tooLarge: return L10n.tr("The GPX file is too large. Use at most 10 MB and 50,000 points.")
        }
    }
}

enum GPXCodec {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumPoints = 50_000

    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> [CLLocationCoordinate2D] {
        guard data.count <= maximumBytes else { throw GPXError.tooLarge }
        let reader = GPXReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let parsed = parser.parse()
        if let error = reader.error { throw error }
        guard parsed, reader.isGPX else { throw GPXError.malformed }
        // Prefer track data; waypoints are often unrelated POIs in the same file.
        let result = !reader.tracks.isEmpty ? reader.tracks
            : (!reader.routes.isEmpty ? reader.routes : reader.waypoints)
        guard !result.isEmpty else { throw GPXError.noPoints }
        return result
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = L10n.tr("Locus Route")) -> String {
        let escapedName = name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
        let points = coordinates.filter(RouteGeometry.isValid).map {
            String(format: "      <trkpt lat=\"%.8f\" lon=\"%.8f\"/>", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude)
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(escapedName)</name><trkseg>
        \(points)
          </trkseg></trk>
        </gpx>
        """
    }
}

private final class GPXReader: NSObject, XMLParserDelegate {
    var tracks: [CLLocationCoordinate2D] = []
    var routes: [CLLocationCoordinate2D] = []
    var waypoints: [CLLocationCoordinate2D] = []
    var error: GPXError?
    var isGPX = false
    private var depth = 0
    private var count = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        if depth == 1 { isGPX = elementName == "gpx" }
        guard isGPX, ["trkpt", "rtept", "wpt"].contains(elementName) else { return }
        guard let lat = attributes["lat"].flatMap(Double.init),
              let lon = attributes["lon"].flatMap(Double.init),
              RouteGeometry.isValid(.init(latitude: lat, longitude: lon)) else {
            error = .invalidCoordinate
            parser.abortParsing()
            return
        }
        count += 1
        guard count <= GPXCodec.maximumPoints else {
            error = .tooLarge
            parser.abortParsing()
            return
        }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        switch elementName {
        case "trkpt": tracks.append(coordinate)
        case "rtept": routes.append(coordinate)
        default: waypoints.append(coordinate)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
    }
}
