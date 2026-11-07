import CoreLocation
import SwiftUI

// Isolated state doubles for rendering production controls. This target has no
// native transport, pairing material, location writes, or networking capability.
enum SpoofStatus: Equatable {
    case idle, connecting, active, reconnecting, stopping, dropped(String)
    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: return L10n.tr("Walk")
        case .run: return L10n.tr("Run")
        case .cycle: return L10n.tr("Cycle")
        case .drive: return L10n.tr("Drive")
        }
    }
    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }
}

@MainActor
final class PairingStore: ObservableObject {
    @Published var hasPairingFile: Bool
    init(scenario: PreviewScenario = .requested) {
        hasPairingFile = scenario != .idle && scenario != .guidePairing
    }
}

@MainActor
final class TunnelDiagnostics: ObservableObject {
    enum State { case unknown, checking, reachable, ready, failed, draining }
    static let shared = TunnelDiagnostics()
    @Published var isDraining = false
    @Published var state: State = .unknown
    var statusLabel: String { L10n.tr("Connection not checked") }
}

@MainActor
final class SpoofSession: ObservableObject {
    struct Favorite {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    @Published var status: SpoofStatus = .idle
    @Published var simulated: CLLocationCoordinate2D?
    @Published var pin: CLLocationCoordinate2D? = .init(latitude: 31.2304, longitude: 121.4737)
    @Published var pinName: String? = "示例公园 · 东门"
    @Published var pinAddress: String? = "示例大道 128 号 · 演示地址"
    @Published var favorites: [Favorite] = []
    @Published var travelMode: TravelMode = .walk
    @Published var joystickActive = false
    @Published var currentRoute: RouteTrack?
    @Published var routeProgress = 0.38
    @Published var routeState: RoutePlaybackStatus = .idle
    var routeSegmentIndex = 0
    var restorationRequired = false
    var isBusy = false
    var canWrite = true
    var canStop: Bool { status == .active || restorationRequired }
    var canRetryRestore = true
    var canSaveTargetFavorite = true
    var isFavoriteTarget: Bool {
        guard let pin else { return false }
        return favorites.contains { $0.coordinate.latitude == pin.latitude && $0.coordinate.longitude == pin.longitude }
    }

    init(scenario: PreviewScenario) {
        if scenario == .guideRestoration {
            restorationRequired = true
            canWrite = false
        } else if scenario.showsActiveRoute {
            status = .active
            // The pending target deliberately differs from the active position.
            simulated = .init(latitude: 31.2296, longitude: 121.4655)
            routeState = .playing
            currentRoute = RouteTrack(name: "预览路线", coordinates: [
                .init(latitude: 31.23, longitude: 121.47),
                .init(latitude: 31.24, longitude: 121.48)
            ])
        }
    }

    func updateJoystick(vector: CGVector) {}
    func stopJoystick() { joystickActive = false }
    func startJoystick(pairing: PairingStore) { joystickActive = true }
    func teleport(to point: CLLocationCoordinate2D, pairing: PairingStore) {}
    func stop(pairing: PairingStore) {}
    func pauseRoute() { routeState = .paused }
    func resumeRoute(pairing: PairingStore) { routeState = .playing }
    func nextRouteSegment(pairing: PairingStore) {}

    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        fallback ?? pinName ?? "预览地点"
    }
    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        favorites.append(Favorite(name: name, coordinate: coordinate))
    }
    func selectTarget(_ coordinate: CLLocationCoordinate2D?) {
        pin = coordinate
        pinName = nil
        pinAddress = nil
    }
}
