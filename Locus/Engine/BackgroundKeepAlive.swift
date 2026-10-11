import CoreLocation
import Foundation

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

/// System fixes can contain software simulation; no value here is called real GPS.
@MainActor
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var simulationActive = false
    private var backgroundEnabled = false
    private var requestedAlways = false
    private var freshRequestedAt: Date?
    private var requestInFlight = false
    private(set) var lastFix: SystemLocationFix?
    var onFix: ((SystemLocationFix?) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?
    var onIssue: ((String?) -> Void)?

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        guard let lastFix, !lastFix.isSimulated else { return nil }
        return lastFix.coordinate
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        configureUpdates()
    }

    func setSimulationActive(_ active: Bool) {
        guard simulationActive != active else { return }
        simulationActive = active
        if active {
            lastFix = nil
            onFix?(nil)
        }
        configureUpdates()
    }

    func setBackgroundEnabled(_ enabled: Bool) {
        backgroundEnabled = enabled
        if !enabled { requestedAlways = false }
        if enabled {
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            else if manager.authorizationStatus == .authorizedWhenInUse, !requestedAlways {
                requestedAlways = true
                manager.requestAlwaysAuthorization()
            }
        }
        configureUpdates()
    }

    func stop() {
        simulationActive = false
        manager.stopUpdatingLocation()
        requestInFlight = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        lastFix = nil
        onFix?(nil)
    }

    func requestFreshSystemFix() {
        guard !simulationActive, !requestInFlight else { return }
        lastFix = nil
        onFix?(nil)
        freshRequestedAt = Date()
        start()
    }

    private func configureUpdates() {
        let authorization = manager.authorizationStatus
        onAuthorization?(authorization)
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
            manager.stopUpdatingLocation()
            requestInFlight = false
            if authorization == .denied || authorization == .restricted {
                onIssue?(L10n.tr("Location permission is unavailable. Enable it in iOS Settings to request a system position."))
            }
            return
        }
        onIssue?(nil)
        if simulationActive, backgroundEnabled, authorization == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.pausesLocationUpdatesAutomatically = true
            if !simulationActive, !requestInFlight {
                requestInFlight = true
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.backgroundEnabled, !self.requestedAlways, self.manager.authorizationStatus == .authorizedWhenInUse {
                self.requestedAlways = true
                self.manager.requestAlwaysAuthorization()
            }
            self.configureUpdates()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.filter { $0.horizontalAccuracy >= 0 }.map(SystemLocationFix.init)
        Task { @MainActor [weak self] in
            guard let self, let fix = fixes.last else { return }
            self.requestInFlight = false
            if let requestedAt = self.freshRequestedAt, fix.timestamp < requestedAt { return }
            self.freshRequestedAt = nil
            self.lastFix = fix
            self.onFix?(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.requestInFlight = false
            self?.onIssue?(message)
        }
    }
}
