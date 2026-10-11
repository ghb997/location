import CoreLocation
import Foundation

@MainActor
protocol PairingProviding: AnyObject, Sendable {
    var hasPairingFile: Bool { get }
    var pairingPath: String { get }
}

struct SystemLocationFix: Equatable, Sendable {
    let point: RoutePoint
    let timestamp: Date
    let horizontalAccuracy: Double
    let isSimulated: Bool

    var coordinate: CLLocationCoordinate2D { point.coordinate }

    init(_ location: CLLocation) {
        point = RoutePoint(location.coordinate)
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        isSimulated = location.sourceInformation?.isSimulatedBySoftware == true
    }
}

@MainActor
protocol LocationKeeping: AnyObject {
    var onFix: ((SystemLocationFix?) -> Void)? { get set }
    var onAuthorization: ((CLAuthorizationStatus) -> Void)? { get set }
    var onIssue: ((String?) -> Void)? { get set }
    func start()
    func stop()
    func requestFreshSystemFix()
    func setSimulationActive(_ active: Bool)
    func setBackgroundEnabled(_ enabled: Bool)
}

/// Only platform services live here. Tests run the production session with
/// controlled transport, clock, location callbacks and isolated preferences.
@MainActor
struct SessionRuntime {
    let locationKeeper: any LocationKeeping
    var monitorsNetwork = true
    var sendsNotifications = true
    var preferences: UserDefaults = .standard
    var targetIP: () -> String = { TunnelConfig.targetIP }

    static func live() -> SessionRuntime {
        #if canImport(UIKit)
        SessionRuntime(locationKeeper: BackgroundKeepAlive())
        #else
        preconditionFailure("Supply platform services when constructing a session outside iOS.")
        #endif
    }

    static func nativeTransport() -> any LocationTransport {
        #if canImport(UIKit)
        NativeLocationTransport()
        #else
        preconditionFailure("Supply a transport when constructing a session outside iOS.")
        #endif
    }
}
