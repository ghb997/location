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
final class PairingStore: ObservableObject {}

@MainActor
final class TunnelDiagnostics: ObservableObject {
    enum State { case idle, reachable, ready }
    static let shared = TunnelDiagnostics()
    @Published var isDraining = false
    @Published var state: State = .idle
    var statusLabel: String { L10n.tr("Not Spoofing") }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var simulated: CLLocationCoordinate2D?
    @Published var pin: CLLocationCoordinate2D? = .init(latitude: 31.23, longitude: 121.47)
    @Published var travelMode: TravelMode = .walk
    @Published var joystickActive = false
    @Published var currentRoute: RouteTrack?
    @Published var routeProgress = 0.38
    @Published var routeState: RoutePlaybackStatus = .idle
    var routeSegmentIndex = 0
    var restorationRequired = false
    var isBusy = false
    var canWrite = true
    var canStop: Bool { status == .active }
    var canRetryRestore = true

    init(scenario: PreviewScenario) {
        if scenario != .idle {
            status = .active
            simulated = pin
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
}
