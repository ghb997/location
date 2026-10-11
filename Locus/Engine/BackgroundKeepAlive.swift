import CoreLocation
import Foundation

/// System fixes can contain software simulation; no value here is called real GPS.
@MainActor
final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate, LocationKeeping {
    private let manager = CLLocationManager()
    private var simulationActive = false
    private var backgroundEnabled = false
    private var requestedAlways = false
    private var updatesRequested = false
    private var needsFreshRequest = false
    private var observedAuthorization: CLAuthorizationStatus?
    private var freshRequest: FreshLocationRequest?
    private lazy var freshController = FreshLocationController(
        request: { [weak self] identifier in self?.beginFreshAttempt(identifier) },
        cancelRequest: { [weak self] in self?.cancelFreshAttempt() }
    )
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
        freshController.onState = { [weak self] state in
            switch state {
            case .idle, .succeeded: self?.onIssue?(nil)
            case .waiting:
                self?.onIssue?(L10n.tr("Getting a fresh system location…"))
            case .retrying:
                self?.onIssue?(L10n.tr("The system returned a cached or unavailable location. Retrying…"))
            case .timedOut:
                self?.onIssue?(L10n.tr("Getting a fresh system location timed out. Tap Refresh system location to try again."))
            }
        }
    }

    func start() {
        updatesRequested = true
        if !simulationActive, lastFix == nil, !freshController.isWaiting { needsFreshRequest = true }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        configureUpdates()
    }

    func setSimulationActive(_ active: Bool) {
        guard simulationActive != active else { return }
        simulationActive = active
        freshController.cancel()
        needsFreshRequest = !active && updatesRequested
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
        updatesRequested = false
        needsFreshRequest = false
        simulationActive = false
        freshController.cancel()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        lastFix = nil
        onFix?(nil)
    }

    func requestFreshSystemFix() {
        guard !simulationActive else { return }
        freshController.cancel()
        needsFreshRequest = true
        lastFix = nil
        onFix?(nil)
        start()
    }

    private func configureUpdates() {
        let authorization = manager.authorizationStatus
        onAuthorization?(authorization)
        guard updatesRequested else { return }
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
            freshController.cancel()
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            lastFix = nil
            onFix?(nil)
            if authorization == .denied || authorization == .restricted {
                onIssue?(L10n.tr("Location permission is unavailable. Enable it in iOS Settings to request a system position."))
            }
            return
        }
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
            if !simulationActive, needsFreshRequest {
                needsFreshRequest = false
                freshController.start()
            }
        }
    }

    private func beginFreshAttempt(_ identifier: UUID) {
        let request = FreshLocationRequest(identifier: identifier, onFix: { [weak self] identifier, fix in
            guard let self, !simulationActive, updatesRequested else { return }
            let authorization = manager.authorizationStatus
            guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
                configureUpdates()
                return
            }
            guard freshController.receive(requestID: identifier, timestamp: fix.timestamp,
                                          horizontalAccuracy: fix.horizontalAccuracy,
                                          isSimulated: fix.isSimulated) else { return }
            lastFix = fix
            onFix?(fix)
        }, onFailure: { [weak self] identifier in
            self?.freshController.fail(requestID: identifier)
        })
        freshRequest = request
        request.start()
    }

    private func cancelFreshAttempt() {
        freshRequest?.cancel()
        freshRequest = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let authorization = self.manager.authorizationStatus
            if self.observedAuthorization != authorization {
                self.observedAuthorization = authorization
                self.freshController.cancel()
                self.needsFreshRequest = self.updatesRequested && !self.simulationActive
            }
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
            // This delegate only owns continuous updates during simulation.
            // Fresh one-shot requests each use a separate delegate and identity.
            guard let self, self.updatesRequested, self.simulationActive,
                  self.backgroundEnabled, let fix = fixes.max(by: { $0.timestamp < $1.timestamp }) else { return }
            self.lastFix = fix
            self.onFix?(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.updatesRequested, self.simulationActive else { return }
            self.onIssue?(message)
        }
    }
}

/// Core Location callbacks do not include request IDs. A manager and delegate
/// per attempt make cancellation and retry ownership explicit.
@MainActor
private final class FreshLocationRequest: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let identifier: UUID
    private let onFix: (UUID, SystemLocationFix) -> Void
    private let onFailure: (UUID) -> Void
    private var active = false

    init(identifier: UUID, onFix: @escaping (UUID, SystemLocationFix) -> Void,
         onFailure: @escaping (UUID) -> Void) {
        self.identifier = identifier
        self.onFix = onFix
        self.onFailure = onFailure
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        active = true
        manager.requestLocation()
    }

    func cancel() {
        active = false
        manager.delegate = nil
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.filter {
            $0.horizontalAccuracy.isFinite && $0.horizontalAccuracy >= 0 && RouteGeometry.isValid($0.coordinate)
        }.max(by: { $0.timestamp < $1.timestamp }).map(SystemLocationFix.init)
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            if let fix { self.onFix(self.identifier, fix) }
            else { self.onFailure(self.identifier) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.onFailure(self.identifier)
        }
    }
}
