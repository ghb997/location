import CoreLocation
import Foundation

enum CoordinateSystem: String, Codable, CaseIterable, Identifiable {
    case wgs84, gcj02

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wgs84: return L10n.tr("WGS84 (GPS / standard GPX)")
        case .gcj02: return L10n.tr("GCJ-02 (mainland China maps)")
        }
    }
}

/// Describes where a value entered the app. Stored coordinates are always the
/// app's WGS84 values; this provenance never triggers a second conversion.
enum CoordinateSource: String, Codable {
    case mapSelection, appleSearch, appleRoute, gpx, manual, legacy
}

enum CoordinateTransformError: LocalizedError {
    case invalidCoordinate, coverageUnavailable, didNotConverge, alreadyCorrected, outsideCoverage

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: return L10n.tr("Enter valid latitude and longitude values.")
        case .coverageUnavailable: return L10n.tr("The offline coordinate coverage data is unavailable. Keep the standard coordinate setting.")
        case .didNotConverge: return L10n.tr("The coordinate conversion did not converge. The original point was kept.")
        case .alreadyCorrected: return L10n.tr("This place already uses standard coordinates and cannot be corrected again.")
        case .outsideCoverage: return L10n.tr("This point is outside the mainland coordinate coverage. Its coordinates were kept.")
        }
    }
}

enum CoordinateTransform {
    static func normalize(_ coordinate: CLLocationCoordinate2D, from system: CoordinateSystem) throws -> CLLocationCoordinate2D {
        try convert(coordinate, from: system, to: .wgs84)
    }

    static func convert(_ coordinate: CLLocationCoordinate2D, from source: CoordinateSystem, to destination: CoordinateSystem) throws -> CLLocationCoordinate2D {
        guard RouteGeometry.isValid(coordinate) else { throw CoordinateTransformError.invalidCoordinate }
        guard source != destination else { return coordinate }
        // Unlike the common rectangular guard, the bundled map-unit polygon
        // leaves Hong Kong, Macau, Taiwan and neighboring countries unchanged.
        guard try OfflineMainlandCoverage.contains(coordinate) else { return coordinate }
        if source == .wgs84 { return forwardUnchecked(coordinate) }

        var estimate = coordinate
        for _ in 0..<20 {
            let projected = forwardUnchecked(estimate)
            let latitudeError = projected.latitude - coordinate.latitude
            let longitudeError = projected.longitude - coordinate.longitude
            if max(abs(latitudeError), abs(longitudeError)) < 1e-9 {
                // Near an approximate coverage boundary, never move a point
                // into an excluded region merely to satisfy the equation.
                guard try OfflineMainlandCoverage.contains(estimate) else { return coordinate }
                return estimate
            }
            estimate.latitude -= latitudeError
            estimate.longitude -= longitudeError
            guard RouteGeometry.isValid(estimate) else { throw CoordinateTransformError.invalidCoordinate }
        }
        throw CoordinateTransformError.didNotConverge
    }

    /// Forward formula ported from wandergis/coordtransform 2.1.2 (MIT).
    /// This is an engineering approximation, not an official Apple algorithm.
    private static func forwardUnchecked(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let semiMajorAxis = 6_378_245.0
        let eccentricitySquared = 0.00669342162296594323
        let x = coordinate.longitude - 105, y = coordinate.latitude - 35
        var latitudeOffset = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        latitudeOffset += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2 / 3
        latitudeOffset += (20*sin(y * .pi) + 40*sin(y/3 * .pi)) * 2 / 3
        latitudeOffset += (160*sin(y/12 * .pi) + 320*sin(y * .pi/30)) * 2 / 3
        var longitudeOffset = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        longitudeOffset += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2 / 3
        longitudeOffset += (20*sin(x * .pi) + 40*sin(x/3 * .pi)) * 2 / 3
        longitudeOffset += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi)) * 2 / 3
        let latitudeRadians = coordinate.latitude * .pi / 180
        let sineLatitude = sin(latitudeRadians)
        let magic = 1 - eccentricitySquared * sineLatitude * sineLatitude
        let rootMagic = sqrt(magic)
        latitudeOffset = latitudeOffset * 180 / ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * rootMagic) * .pi)
        longitudeOffset = longitudeOffset * 180 / (semiMajorAxis / rootMagic * cos(latitudeRadians) * .pi)
        return .init(latitude: coordinate.latitude + latitudeOffset, longitude: coordinate.longitude + longitudeOffset)
    }
}
