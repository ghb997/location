import CoreLocation
import Foundation

/// Prepared once per track/coordinate-setting revision, never per heartbeat.
/// Original points and segment boundaries remain intact for playback/export.
struct RouteDisplayGeometry: Sendable {
    struct Segment: Identifiable, Sendable {
        let id: UUID
        let coordinates: [CLLocationCoordinate2D]
    }
    let segments: [Segment]
    let remainingDistances: [Double]

    init(track: RouteTrack, project: (CLLocationCoordinate2D) throws -> CLLocationCoordinate2D = { $0 }) throws {
        var rendered: [Segment] = []
        var distances: [Double] = []
        for segment in track.segments {
            try Task.checkCancellation()
            rendered.append(Segment(id: segment.id, coordinates: try segment.points.map {
                try Task.checkCancellation()
                return try project($0.coordinate)
            }))
            distances.append(segment.distance)
        }
        var remaining = 0.0
        for index in distances.indices.reversed() {
            remaining += distances[index]
            distances[index] = remaining
        }
        segments = rendered
        remainingDistances = distances
    }
}
