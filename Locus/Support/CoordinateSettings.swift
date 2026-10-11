import CoreLocation
import Foundation

enum CoordinateSettings {
    static let mapKey = "locus.coordinates.mapSystem"
    static let serviceKey = "locus.coordinates.serviceSystem"
    static let defaultValue = CoordinateSystem.wgs84.rawValue

    static func mapSystem(defaults: UserDefaults = .standard) -> CoordinateSystem {
        CoordinateSystem(rawValue: defaults.string(forKey: mapKey) ?? "") ?? .wgs84
    }

    static func serviceSystem(defaults: UserDefaults = .standard) -> CoordinateSystem {
        CoordinateSystem(rawValue: defaults.string(forKey: serviceKey) ?? "") ?? .wgs84
    }

    static func mapInput(_ coordinate: CLLocationCoordinate2D, defaults: UserDefaults = .standard) throws -> CLLocationCoordinate2D {
        try CoordinateTransform.normalize(coordinate, from: mapSystem(defaults: defaults))
    }

    static func mapOutput(_ coordinate: CLLocationCoordinate2D, defaults: UserDefaults = .standard) throws -> CLLocationCoordinate2D {
        try CoordinateTransform.convert(coordinate, from: .wgs84, to: mapSystem(defaults: defaults))
    }

    static func serviceInput(_ coordinate: CLLocationCoordinate2D, defaults: UserDefaults = .standard) throws -> CLLocationCoordinate2D {
        try CoordinateTransform.convert(coordinate, from: .wgs84, to: serviceSystem(defaults: defaults))
    }

    static func serviceOutput(_ coordinate: CLLocationCoordinate2D, defaults: UserDefaults = .standard) throws -> CLLocationCoordinate2D {
        try CoordinateTransform.normalize(coordinate, from: serviceSystem(defaults: defaults))
    }
}
