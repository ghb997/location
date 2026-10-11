import CoreLocation
import Foundation

struct RoutePoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RouteSegment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var points: [RoutePoint]

    init(id: UUID = UUID(), points: [RoutePoint]) {
        self.id = id
        self.points = points
    }

    init(coordinates: [CLLocationCoordinate2D]) {
        self.init(points: coordinates.map(RoutePoint.init))
    }

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    var canPlay: Bool { points.count >= 2 && points.allSatisfy { RouteGeometry.isValid($0.coordinate) } }
    var distance: Double { zip(points, points.dropFirst()).reduce(0) { $0 + RouteGeometry.distance(from: $1.0.coordinate, to: $1.1.coordinate) } }
}

struct RouteTrack: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case track, route, waypoints }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    var segments: [RouteSegment]

    init(id: UUID = UUID(), name: String, kind: Kind = .track, segments: [RouteSegment]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.segments = segments
    }

    init(name: String = L10n.tr("Locus Route"), coordinates: [CLLocationCoordinate2D]) {
        self.init(name: name, segments: [RouteSegment(coordinates: coordinates)])
    }

    /// Compatibility/display accessor. Playback must iterate segments separately.
    var coordinates: [CLLocationCoordinate2D] { segments.flatMap(\.coordinates) }
    var distance: Double { segments.reduce(0) { $0 + $1.distance } }
    var canPlay: Bool { segments.contains(where: \.canPlay) }
}

struct RouteDocument: Codable, Equatable, Sendable {
    var tracks: [RouteTrack]

    var preferredTrack: RouteTrack? {
        tracks.first(where: { $0.kind == .track && !$0.segments.allSatisfy { $0.points.isEmpty } })
            ?? tracks.first(where: { $0.kind == .route && !$0.segments.allSatisfy { $0.points.isEmpty } })
            ?? tracks.first(where: { !$0.segments.allSatisfy { $0.points.isEmpty } })
    }
}
