import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

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

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case stopping
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return L10n.tr("Not Spoofing")
        case .connecting: return L10n.tr("Starting…")
        case .active: return L10n.tr("Spoofing")
        case .reconnecting: return L10n.tr("Reconnecting…")
        case .stopping: return L10n.tr("Stopping…")
        case .dropped: return L10n.tr("Interrupted")
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    @Published var pendingGPXURL: URL?

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var generation = 0
    private var isStopping = false
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    var canStop: Bool {
        simulated != nil || isBusy || status.isDropped
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard !isBusy, !isStopping else { return }
        guard pairing.hasPairingFile else {
            lastError = L10n.tr("Import an RPPairing file in Settings first.")
            return
        }
        guard RouteGeometry.isValid(coordinate) else {
            lastError = LocationEngineError.invalidCoordinate.localizedDescription
            return
        }
        cancelMovement()
        let token = generation
        pin = coordinate
        Task { await apply(coordinate, pairing: pairing, markRecent: true, token: token) }
    }

    func stop(pairing: PairingStore) {
        guard !isStopping else { return }
        cancelMovement()
        stopResend()
        isStopping = true
        isBusy = true
        status = .stopping
        Task {
            // The engine serializes this after any in-flight write. Generation checks
            // keep a completed old write from restarting timers or changing UI state.
            let result = await LocationEngine.clear()
            isBusy = false
            isStopping = false
            endBackground()
            switch result {
            case .success:
                simulated = nil
                status = .idle
                lastError = nil
                locationKeeper.start()
            case .failure(let error):
                lastError = error.localizedDescription
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            }
        }
    }

    private func cancelMovement() {
        generation += 1
        routeTask?.cancel()
        routeTask = nil
        stopJoystick()
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard !isBusy, !isStopping else { return }
        guard pairing.hasPairingFile else {
            lastError = L10n.tr("Import an RPPairing file in Settings first.")
            return
        }
        guard let start = simulated ?? pin ?? locationKeeper.lastKnownCoordinate else {
            lastError = L10n.tr("Drop a pin or teleport somewhere before using the joystick.")
            return
        }
        cancelMovement()
        let token = generation
        Task {
            if simulated == nil {
                guard await apply(start, pairing: pairing, markRecent: false, token: token) else { return }
            }
            guard token == generation, !isStopping else { return }
            joystickActive = true
            joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tickJoystick(pairing: pairing, token: token) }
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard !isBusy, !isStopping else { return }
        guard pairing.hasPairingFile else {
            lastError = L10n.tr("Import an RPPairing file in Settings first.")
            return
        }
        guard coordinates.count >= 2, coordinates.allSatisfy(RouteGeometry.isValid) else {
            lastError = L10n.tr("Build or draw a route first.")
            return
        }
        cancelMovement()
        let token = generation
        let mode = travelMode
        routeTask = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.routeTask = nil } }
            guard await self.apply(coordinates[0], pairing: pairing, markRecent: true, token: token) else { return }
            for (previous, next) in zip(coordinates, coordinates.dropFirst()) {
                guard !Task.isCancelled, token == self.generation else { return }
                let distance = RouteGeometry.distance(from: previous, to: next)
                if distance < 0.01 { continue }
                let speed = max(0.8, mode.baseSpeed * Double.random(in: 0.88...1.12))
                let stepMeters = min(12, max(4, speed * 0.5))
                let steps = max(1, Int(ceil(distance / stepMeters)))
                let delay = RouteGeometry.stepDelay(distance: distance, steps: steps, speed: speed)
                for i in 1...steps {
                    do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    catch { return }
                    guard !Task.isCancelled, token == self.generation else { return }
                    let coordinate = RouteGeometry.interpolate(from: previous, to: next, fraction: Double(i) / Double(steps))
                    // Heartbeats skip while a route is running, so a route never drops
                    // an update because a keep-alive acquired the engine first.
                    guard await self.apply(coordinate, pairing: pairing, markRecent: false, token: token) else { return }
                }
            }
        }
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" || trimmed == L10n.tr("Favorite") { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    @discardableResult
    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool, token: Int) async -> Bool {
        guard !Task.isCancelled, token == generation, !isBusy, !isStopping else { return false }
        if status == .idle { status = .connecting }
        else if status.isDropped { status = .reconnecting }
        isBusy = true
        let result = await LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        guard token == generation, !isStopping else { return false }
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            if markRecent { pushRecent(coordinate) }
            return true
        case .failure(let error):
            let previousError = lastError
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                if previousError != error.localizedDescription { postDropNotification(error.localizedDescription) }
            } else {
                status = .idle
            }
            stopJoystick()
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore, token: Int) async {
        guard joystickActive, !isBusy, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude
        let speed = travelMode.baseSpeed * min(1.0, magnitude) * Double.random(in: 0.9...1.1)
        let meters = speed * 0.25
        let next = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        await apply(next, pairing: pairing, markRecent: false, token: token)
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isBusy, !self.isStopping,
                      self.routeTask == nil,
                      let simulated = self.simulated else { return }
                await self.apply(simulated, pairing: pairing, markRecent: false, token: self.generation)
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Locus spoof dropped")
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * max(0.000001, cos(coordinate.latitude * .pi / 180))) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: min(90, max(-90, coordinate.latitude + dLat)), longitude: RouteGeometry.wrapLongitude(coordinate.longitude + dLon))
    }
}
