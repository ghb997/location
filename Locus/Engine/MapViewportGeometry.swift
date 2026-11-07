import CoreLocation
import Foundation

/// Normalized Web Mercator bounds. X may cross the world seam; do not split or
/// clamp it before passing the rectangle to a map renderer that wraps longitude.
struct MapViewportBounds: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum MapViewportGeometry {
    private static let circumference = 40_075_016.686

    static func point(_ coordinate: CLLocationCoordinate2D, meters: Double = 1_200) -> MapViewportBounds {
        let latitude = min(85.05112878, max(-85.05112878, coordinate.latitude))
        let x = (coordinate.longitude + 180) / 360
        let y = projectedY(latitude)
        let span = min(1, max(1, meters) / (circumference * max(0.01, cos(latitude * .pi / 180))))
        return .init(x: x - span / 2, y: y - span / 2, width: span, height: span)
    }

    /// Find the shortest circular longitude interval, including routes crossing
    /// the antimeridian. Prepared with display geometry, never per heartbeat.
    static func bounds(_ coordinates: [CLLocationCoordinate2D]) -> MapViewportBounds? {
        guard let first = coordinates.first else { return nil }
        let valid = coordinates.filter(RouteGeometry.isValid)
        guard !valid.isEmpty else { return nil }
        let xs = valid.map { ($0.longitude + 180) / 360 }.sorted()
        var gap = -Double.infinity
        var start = xs[0]
        for index in xs.indices {
            let next = index + 1 < xs.count ? xs[index + 1] : xs[0] + 1
            if next - xs[index] > gap {
                gap = next - xs[index]
                start = next.truncatingRemainder(dividingBy: 1)
            }
        }
        let ys = valid.map { projectedY($0.latitude) }
        let minY = ys.min()!, maxY = ys.max()!
        let floor = point(valid.first ?? first, meters: 400)
        let width = max(floor.width, 1 - gap), height = max(floor.height, maxY - minY)
        return .init(x: start + (1 - gap - width) / 2,
                     y: (minY + maxY - height) / 2, width: width, height: height)
    }

    /// Expand and offset the full map rectangle so content lands in the visible
    /// space between overlays. All dimensions/insets are measured in one view.
    static func fit(_ content: MapViewportBounds, width: Double, height: Double,
                    top: Double, bottom: Double, left: Double = 16, right: Double = 16,
                    padding: Double = 20) -> MapViewportBounds? {
        guard [content.x, content.y, content.width, content.height, width, height,
               top, bottom, left, right, padding].allSatisfy(\.isFinite),
              width > 0, height > 0, content.width > 0, content.height > 0 else { return nil }
        let leading = max(0, left), trailing = max(0, right)
        let upper = max(0, top), lower = max(0, bottom)
        let availableWidth = width - leading - trailing
        let availableHeight = height - upper - lower
        guard availableWidth > 1, availableHeight > 1 else { return nil }
        let inset = min(max(0, padding), min(availableWidth, availableHeight) * 0.2)
        let scale = max(content.width / (availableWidth - 2 * inset),
                        content.height / (availableHeight - 2 * inset))
        let fullWidth = width * scale, fullHeight = height * scale
        let centerX = content.x + content.width / 2 - (leading - trailing) * scale / 2
        let centerY = content.y + content.height / 2 - (upper - lower) * scale / 2
        return .init(x: centerX - fullWidth / 2, y: centerY - fullHeight / 2,
                     width: fullWidth, height: fullHeight)
    }

    private static func projectedY(_ latitude: Double) -> Double {
        let radians = min(85.05112878, max(-85.05112878, latitude)) * .pi / 180
        return (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
    }
}
