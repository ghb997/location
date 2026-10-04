import CoreLocation
import Foundation

enum RouteGeometry {
    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && CLLocationCoordinate2DIsValid(coordinate)
    }

    static func interpolate(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        // Follow the short arc across the date line, rather than crossing the globe.
        let longitudeDelta = (b.longitude - a.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: wrapLongitude(a.longitude + longitudeDelta * fraction)
        )
    }

    static func wrapLongitude(_ value: Double) -> Double {
        let wrapped = (value + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }

    static func stepDelay(distance: Double, steps: Int, speed: Double) -> Double {
        guard distance.isFinite, distance >= 0, steps > 0, speed.isFinite, speed > 0 else { return 0 }
        return distance / Double(steps) / speed
    }

    static func sample(_ coordinates: [CLLocationCoordinate2D], every meters: Double, limit: Int = 50_000) -> [CLLocationCoordinate2D] {
        guard meters.isFinite, meters > 0, limit >= 2,
              coordinates.allSatisfy(isValid) else { return [] }
        guard coordinates.count > 1 else { return coordinates }
        // Preflight before allocating. Very long tracks stay as original waypoints;
        // playback interpolates one segment at a time without allocating millions of points.
        var required = 1.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            required += max(1, ceil(distance(from: a, to: b) / meters))
            if required > Double(limit) { return coordinates }
        }
        var result = [coordinates[0]]
        result.reserveCapacity(Int(required))
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let steps = max(1, Int(ceil(distance(from: a, to: b) / meters)))
            for i in 1...steps {
                result.append(interpolate(from: a, to: b, fraction: Double(i) / Double(steps)))
            }
        }
        return result
    }

    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
