import CoreLocation
import Foundation
import MapKit

enum RouteBuildError: LocalizedError {
    case network, service, noRoute, invalidCoordinates

    var errorDescription: String? {
        switch self {
        case .network: return L10n.tr("The route could not be loaded because the network is unavailable. Check the connection and try again.")
        case .service: return L10n.tr("The map routing service is unavailable. Try again later or import a GPX route.")
        case .noRoute: return L10n.tr("No road route is available between these points. Choose another start or destination.")
        case .invalidCoordinates: return L10n.tr("Enter valid route start and destination coordinates.")
        }
    }
}

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        guard RouteGeometry.isValid(start), RouteGeometry.isValid(end) else { throw RouteBuildError.invalidCoordinates }
        let serviceSystem = CoordinateSettings.serviceSystem()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: try CoordinateTransform.convert(start, from: .wgs84, to: serviceSystem)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: try CoordinateTransform.convert(end, from: .wgs84, to: serviceSystem)))
        request.transportType = mode.mkTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response: MKDirections.Response
        do {
            response = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await directions.calculate()
            } onCancel: {
                directions.cancel()
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            let details = error as NSError
            let underlying = details.userInfo[NSUnderlyingErrorKey] as? NSError
            if details.domain == NSURLErrorDomain || underlying?.domain == NSURLErrorDomain {
                throw RouteBuildError.network
            }
            if details.domain == MKErrorDomain,
               details.code == MKError.Code.directionsNotFound.rawValue || details.code == MKError.Code.placemarkNotFound.rawValue {
                throw RouteBuildError.noRoute
            }
            throw RouteBuildError.service
        }
        try Task.checkCancellation()
        guard let route = response.routes.first else {
            throw RouteBuildError.noRoute
        }
        guard route.polyline.pointCount >= 2 else { throw RouteBuildError.noRoute }
        var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        return try coordinates.map { try CoordinateTransform.normalize($0, from: serviceSystem) }
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        RouteGeometry.sample(coordinates, every: meters)
    }
}
