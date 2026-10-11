import CoreLocation
import Foundation

/// A geographic guard, not a legal boundary or a survey-grade coverage map.
/// Natural Earth 5.1.1 map units (GU_A3 == CHN), at 1:10 million scale.
/// Hong Kong, Macau and Taiwan are separate map units and are not included.
enum OfflineMainlandCoverage {
    static func contains(_ coordinate: CLLocationCoordinate2D) throws -> Bool {
        guard RouteGeometry.isValid(coordinate) else { throw CoordinateTransformError.invalidCoordinate }
        let polygons = try geometry.get()
        return polygons.contains { $0.contains(coordinate) }
    }

    private static let geometry: Result<[Polygon], Error> = Result {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "mainland-coverage", withExtension: "json", subdirectory: "CoordinateData")
                ?? bundle.url(forResource: "mainland-coverage", withExtension: "json") else {
            throw CoordinateTransformError.coverageUnavailable
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let json = object as? [String: Any], json["type"] as? String == "MultiPolygon",
              let coordinates = json["coordinates"] as? [[[[Double]]]], !coordinates.isEmpty else {
            throw CoordinateTransformError.coverageUnavailable
        }
        let polygons = try coordinates.map(Polygon.init)
        guard !polygons.isEmpty else { throw CoordinateTransformError.coverageUnavailable }
        return polygons
    }

    private struct Bounds {
        let minX: Double, maxX: Double, minY: Double, maxY: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.longitude >= minX && coordinate.longitude <= maxX
                && coordinate.latitude >= minY && coordinate.latitude <= maxY
        }
    }

    private struct Edge {
        let x1: Double, y1: Double, x2: Double, y2: Double
    }

    private struct Ring {
        let bounds: Bounds
        // Index edges by latitude so normalizing a large GPX does not scan
        // thousands of unrelated coastline vertices for every track point.
        let latitudeBands: [Int: [Edge]]

        init(_ points: [[Double]]) throws {
            guard points.count >= 4, points.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else {
                throw CoordinateTransformError.coverageUnavailable
            }
            bounds = Bounds(minX: points.map { $0[0] }.min()!, maxX: points.map { $0[0] }.max()!,
                            minY: points.map { $0[1] }.min()!, maxY: points.map { $0[1] }.max()!)
            var bands: [Int: [Edge]] = [:]
            for (first, second) in zip(points, points.dropFirst()) {
                let edge = Edge(x1: first[0], y1: first[1], x2: second[0], y2: second[1])
                for band in Int(floor(min(edge.y1, edge.y2) * 4))...Int(floor(max(edge.y1, edge.y2) * 4)) {
                    bands[band, default: []].append(edge)
                }
            }
            latitudeBands = bands
        }

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            guard bounds.contains(coordinate) else { return false }
            let x = coordinate.longitude, y = coordinate.latitude
            var inside = false
            for edge in latitudeBands[Int(floor(y * 4))] ?? [] {
                let cross = (x - edge.x1) * (edge.y2 - edge.y1) - (y - edge.y1) * (edge.x2 - edge.x1)
                if abs(cross) <= 1e-12,
                   x >= min(edge.x1, edge.x2), x <= max(edge.x1, edge.x2),
                   y >= min(edge.y1, edge.y2), y <= max(edge.y1, edge.y2) {
                    return true
                }
                if (edge.y1 > y) != (edge.y2 > y),
                   x < (edge.x2 - edge.x1) * (y - edge.y1) / (edge.y2 - edge.y1) + edge.x1 {
                    inside.toggle()
                }
            }
            return inside
        }
    }

    private struct Polygon {
        let exterior: Ring
        let holes: [Ring]

        init(_ rings: [[[Double]]]) throws {
            guard let first = rings.first else { throw CoordinateTransformError.coverageUnavailable }
            exterior = try Ring(first)
            holes = try rings.dropFirst().map(Ring.init)
        }

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            exterior.contains(coordinate) && !holes.contains { $0.contains(coordinate) }
        }
    }
}
