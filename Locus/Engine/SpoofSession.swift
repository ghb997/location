import CoreLocation
import Foundation
import Combine
import Network
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
    @Published var pinSource: CoordinateSource = .manual
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published var joystickActive = false
    @Published var pendingGPXURL: URL?
    @Published var draftTrack: RouteTrack?
    @Published private(set) var currentRoute: RouteTrack?
    @Published private(set) var routePlayback = RoutePlaybackSnapshot()
    @Published private(set) var restorationRequired = false
    @Published private(set) var latestFix: SystemLocationFix?
    @Published private(set) var simulationStartFix: SystemLocationFix?
    @Published private(set) var restoredFix: SystemLocationFix?
    @Published private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationIssue: String?
    @Published var backgroundEnabled = UserDefaults.standard.bool(forKey: "locus.backgroundEnabled") {
        didSet {
            UserDefaults.standard.set(backgroundEnabled, forKey: "locus.backgroundEnabled")
            locationKeeper.setBackgroundEnabled(backgroundEnabled)
            if !backgroundEnabled { endBackground() }
        }
    }
    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var operationEpoch = SessionOperationEpoch()
    private var generation: Int { operationEpoch.value }
    private var isStopping = false
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var routePreparationTask: Task<RoutePlaybackCore?, Never>?
    private var routeIsPreparing = false
    private var routeCore: RoutePlaybackCore?
    private var pendingPauseReason: RoutePauseReason = .user
    private var retryTask: Task<Void, Never>?
    private var retryEpoch = SessionOperationEpoch()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private var lastJoystickTick = 0.0
    private let locationKeeper = BackgroundKeepAlive()
    private let clock: PlaybackClock
    private let transport: any LocationTransport
    private let restorationStore: RestorationRecordStore
    private let pathMonitor = NWPathMonitor()
    private var networkValidationTask: Task<Void, Never>?
    private var lastNetworkSignature: String?
    private weak var activePairing: PairingStore?
    private var diagnosticsSubscription: AnyCancellable?
    private var pairingWorkerSubscription: AnyCancellable?
    private weak var pairingHost: PairOnDeviceService?
    private var lastNotifiedDropReason: String?
    private var restoreContext: RestorationRecord?
    private var confirmedStopAt: Date?

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"
    init(clock: PlaybackClock = PlaybackClock(), restorationStore: RestorationRecordStore = RestorationRecordStore(),
         transport: (any LocationTransport)? = nil) {
        self.clock = clock
        self.transport = transport ?? NativeLocationTransport()
        self.restorationStore = restorationStore
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        if let context = restorationStore.record {
            restoreContext = context
            restorationRequired = true
            status = .dropped(L10n.tr("A previous simulation may still be active. Restore the system location before starting again."))
        } else if restorationStore.hasPendingRecord {
            restorationRequired = true
            status = .dropped(L10n.tr("The restoration record could not be read. Check the pairing file and restore the system location before starting."))
        }
        locationKeeper.onFix = { [weak self] fix in
            guard let self else { return }
            latestFix = fix
            if status == .idle, !restorationRequired, let confirmedStopAt, let fix,
               !fix.isSimulated, fix.timestamp >= confirmedStopAt {
                restoredFix = fix
            }
        }
        locationKeeper.onAuthorization = { [weak self] in self?.locationAuthorization = $0 }
        locationKeeper.onIssue = { [weak self] in self?.locationIssue = $0 }
        locationKeeper.setBackgroundEnabled(backgroundEnabled)
        diagnosticsSubscription = TunnelDiagnostics.shared.$isDraining.sink { [weak self] _ in self?.objectWillChange.send() }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let signature = "\(path.status)|\(interfaces)|\(path.isExpensive)"
            let available = path.status == .satisfied
            Task { @MainActor in self?.networkPathChanged(signature: signature, available: available) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.ghb997.location.path"))
    }

    deinit {
        pathMonitor.cancel()
        resendTimer?.invalidate()
        joystickTimer?.invalidate()
        routeTask?.cancel()
        routePreparationTask?.cancel()
        retryTask?.cancel()
        networkValidationTask?.cancel()
    }

    var routeState: RoutePlaybackStatus { routePlayback.status }
    var pausedReason: RoutePauseReason? { routePlayback.pauseReason }
    var routeProgress: Double { routePlayback.progress }
    var routeSegmentIndex: Int { routePlayback.segmentIndex }
    var canWrite: Bool { !isBusy && !isStopping && !transport.isDraining && pairingHost?.isWorkerRunning != true }
    var canRetryRestore: Bool { !isStopping && !transport.isStopPending && pairingHost?.isWorkerRunning != true }
    var isSpoofing: Bool { status == .active || status == .reconnecting }
    var canStop: Bool { restorationRequired || simulated != nil || isBusy || status.isDropped }
    var systemCoordinate: CLLocationCoordinate2D? {
        guard !canStop, let latestFix, !latestFix.isSimulated else { return nil }
        return latestFix.coordinate
    }
    /// Kept for source compatibility; callers must label it as a system fix.
    var realCoordinate: CLLocationCoordinate2D? { systemCoordinate }

    func startLocationUpdates() { locationKeeper.start() }
    func requestLatestLocation() { locationKeeper.requestFreshSystemFix() }

    func observePairingWorker(_ host: PairOnDeviceService) {
        pairingHost = host
        pairingWorkerSubscription = host.$isWorkerRunning.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func handleForeground(pairing: PairingStore? = nil) {
        if let pairing { activePairing = pairing }
        if canStop { validateConnection() }
        else { locationKeeper.requestFreshSystemFix() }
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard canWrite, canStart(pairing: pairing) else { return }
        guard RouteGeometry.isValid(coordinate) else {
            lastError = LocationEngineError.invalidCoordinate.localizedDescription
            return
        }
        activePairing = pairing
        let previousCore = routeCore
        cancelMovement(resetRoute: false)
        let token = generation
        pin = coordinate
        Task {
            let succeeded = await apply(coordinate, pairing: pairing, markRecent: true, token: token)
            guard operationEpoch.accepts(token) else { return }
            if succeeded {
                routeCore = nil
                currentRoute = nil
                publishRoute()
            } else if var previousCore {
                previousCore.pause(.transportInterrupted)
                routeCore = previousCore
                currentRoute = previousCore.track
                publishRoute()
            }
        }
    }

    func stop(pairing: PairingStore) {
        guard !isStopping else { return }
        guard pairingHost?.isWorkerRunning != true else {
            lastError = L10n.tr("Wait for the native pairing listener to finish before changing the simulation.")
            return
        }
        activePairing = pairing
        let needsRecovery = restorationRequired || simulated != nil
        cancelMovement(resetRoute: true)
        stopResend()
        isStopping = true
        isBusy = true
        status = .stopping
        transport.cancelPendingPreparation()
        Task {
            // Submission on MainActor plus the engine's serial queue preserves Set → Clear.
            // The UI remains stopping until the native write and queued clear really finish.
            let result = await transport.clear(
                pairingPath: needsRecovery ? (pairing.hasPairingFile ? pairing.pairingPath : restoreContext?.pairingPath) : nil,
                deviceIP: needsRecovery ? (restoreContext?.deviceIP ?? TunnelConfig.targetIP) : nil
            )
            isBusy = false
            isStopping = false
            endBackground()
            locationKeeper.stop()
            switch result {
            case .success:
                simulated = nil
                status = .idle
                lastError = nil
                lastNotifiedDropReason = nil
                clearRestoreMarker()
                confirmedStopAt = Date()
                restoredFix = nil
                locationKeeper.requestFreshSystemFix()
            case .failure(let error):
                lastError = error.localizedDescription
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            }
        }
    }

    private func canStart(pairing: PairingStore) -> Bool {
        if restorationRequired && simulated == nil {
            lastError = L10n.tr("Restore the previous simulation before starting a new location.")
            return false
        }
        guard pairing.hasPairingFile else {
            lastError = L10n.tr("Import an RPPairing file in Settings first.")
            return false
        }
        return true
    }

    private func cancelMovement(resetRoute: Bool) {
        operationEpoch.invalidate()
        routeTask?.cancel()
        routeTask = nil
        routePreparationTask?.cancel()
        routePreparationTask = nil
        routeIsPreparing = false
        cancelRetries()
        stopJoystick()
        if resetRoute {
            routeCore = nil
            currentRoute = nil
            publishRoute()
        } else if routeCore != nil {
            routeCore?.pause(.user)
            publishRoute()
        }
    }

    func startJoystick(pairing: PairingStore) {
        guard canWrite, canStart(pairing: pairing) else { return }
        guard let start = simulated ?? pin ?? systemCoordinate else {
            lastError = L10n.tr("Drop a pin or teleport somewhere before using the joystick.")
            return
        }
        activePairing = pairing
        cancelMovement(resetRoute: false)
        let token = generation
        Task {
            if simulated == nil {
                guard await apply(start, pairing: pairing, markRecent: false, token: token) else { return }
            }
            guard operationEpoch.accepts(token), !isStopping else { return }
            routeCore = nil
            currentRoute = nil
            publishRoute()
            joystickActive = true
            lastJoystickTick = clock.now
            joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tickJoystick(pairing: pairing, token: token) }
            }
        }
    }

    func updateJoystick(vector: CGVector) { joystickVector = vector }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        followRoute(RouteTrack(coordinates: coordinates), pairing: pairing)
    }

    func followRoute(_ track: RouteTrack, pairing: PairingStore) {
        guard canWrite, canStart(pairing: pairing) else { return }
        guard track.segments.contains(where: { $0.points.count >= 2 }) else {
            lastError = L10n.tr("Build or draw a route first.")
            return
        }
        activePairing = pairing
        let previous = routeCore
        cancelMovement(resetRoute: false)
        let token = generation
        let speed = travelMode.baseSpeed
        routeCore = nil
        currentRoute = track
        publishRoute()
        isBusy = true
        routeIsPreparing = true
        let preparation = Task.detached(priority: .userInitiated) { () -> RoutePlaybackCore? in
            guard track.canPlay, track.segments.allSatisfy({ segment in
                segment.points.allSatisfy { RouteGeometry.isValid($0.coordinate) }
            }) else { return nil }
            return RoutePlaybackCore(track: track, speed: speed)
        }
        routePreparationTask = preparation
        routeTask = Task { [weak self] in
            let prepared = await preparation.value
            guard let self, operationEpoch.accepts(token), !isStopping else { return }
            routePreparationTask = nil
            routeIsPreparing = false
            isBusy = false
            routeTask = nil
            guard var prepared else {
                routeCore = previous
                currentRoute = previous?.track
                publishRoute()
                lastError = LocationEngineError.invalidCoordinate.localizedDescription
                return
            }
            if Task.isCancelled || routePlayback.status == .pausing {
                prepared.pause(pendingPauseReason)
                routeCore = prepared
                publishRoute()
                return
            }
            routeCore = prepared
            publishRoute()
            launchRoute(pairing: pairing, token: token, rollback: previous, markRecent: true)
        }
    }

    func pauseRoute(reason: RoutePauseReason = .user) {
        if routeIsPreparing {
            pendingPauseReason = reason
            routePlayback.status = .pausing
            routeTask?.cancel()
            routePreparationTask?.cancel()
            return
        }
        guard routeCore?.snapshot.status == .playing || (routeCore?.snapshot.status == .idle && routeTask != nil) else { return }
        pendingPauseReason = reason
        routeCore?.requestPause()
        publishRoute()
        // Keep generation unchanged: a submitted native set still owns isBusy and
        // its successful result becomes the final acknowledged pause position.
        routeTask?.cancel()
        transport.cancelPendingPreparation()
        if routeTask == nil {
            routeCore?.pause(reason)
            publishRoute()
        }
    }

    func resumeRoute(pairing: PairingStore) {
        guard canWrite, canStart(pairing: pairing), routeTask == nil,
              routeCore?.snapshot.status == .paused else { return }
        activePairing = pairing
        cancelRetries()
        launchRoute(pairing: pairing, token: generation, rollback: nil, markRecent: false)
    }

    func nextRouteSegment(pairing: PairingStore) {
        guard canWrite, canStart(pairing: pairing), routeTask == nil,
              var core = routeCore, core.snapshot.status == .awaitingNextSegment else { return }
        let previous = core
        guard core.selectNextSegment() != nil else { return }
        activePairing = pairing
        operationEpoch.invalidate()
        cancelRetries()
        routeCore = core
        publishRoute()
        launchRoute(pairing: pairing, token: generation, rollback: previous, markRecent: false)
    }

    func reconnect(pairing: PairingStore) {
        guard canWrite, let coordinate = simulated else { return }
        activePairing = pairing
        cancelRetries()
        let token = generation
        Task { await apply(coordinate, pairing: pairing, markRecent: false, token: token) }
    }

    private func launchRoute(pairing: PairingStore, token: Int, rollback: RoutePlaybackCore?, markRecent: Bool) {
        pendingPauseReason = .user
        routeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if operationEpoch.accepts(token) {
                    if routeCore?.snapshot.status == .pausing { routeCore?.pause(pendingPauseReason) }
                    routeTask = nil
                    publishRoute()
                }
            }
            guard let firstSample = routeCore?.confirmed ?? routeCore?.plan?.sample(at: 0) else { return }
            guard await apply(firstSample.point.coordinate, pairing: pairing, markRecent: markRecent, token: token, allowRetry: false) else {
                guard operationEpoch.accepts(token) else { return }
                if Task.isCancelled, routeCore?.snapshot.status == .pausing {
                    routeCore?.pause(pendingPauseReason)
                    publishRoute()
                    return
                }
                if var rollback {
                    rollback.pause(.transportInterrupted)
                    routeCore = rollback
                    currentRoute = rollback.track
                } else { routeCore?.pause(.transportInterrupted) }
                publishRoute()
                scheduleRetries(pairing: pairing, token: token)
                return
            }
            guard operationEpoch.accepts(token) else { return }
            if Task.isCancelled || routeCore?.snapshot.status == .pausing {
                routeCore?.confirm(firstSample, at: clock.now)
                routeCore?.pause(pendingPauseReason)
                publishRoute()
                return
            }
            routeCore?.start(at: clock.now)
            routeCore?.confirm(firstSample, at: clock.now)
            publishRoute()
            while !Task.isCancelled, operationEpoch.accepts(token), routeCore?.snapshot.status == .playing {
                guard let deadline = routeCore?.nextDeadline(after: clock.now) else { return }
                do { try await clock.sleep(until: deadline) } catch { return }
                guard !Task.isCancelled, operationEpoch.accepts(token) else { return }
                let started = clock.now
                guard let sample = routeCore?.proposedSample(at: started) else { publishRoute(); return }
                guard await apply(sample.point.coordinate, pairing: pairing, markRecent: false, token: token, allowRetry: false) else {
                    guard operationEpoch.accepts(token) else { return }
                    routeCore?.pause(.transportInterrupted)
                    publishRoute()
                    scheduleRetries(pairing: pairing, token: token)
                    return
                }
                guard operationEpoch.accepts(token) else { return }
                routeCore?.confirm(sample, at: clock.now, writeStartedAt: started)
                if Task.isCancelled, pendingPauseReason != .user {
                    routeCore?.pause(pendingPauseReason)
                }
                publishRoute()
            }
        }
    }

    private func publishRoute() {
        routePlayback = routeCore?.snapshot ?? RoutePlaybackSnapshot()
    }

    private func markRestoreNeeded(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
        let context = RestorationRecord(point: RoutePoint(coordinate), pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
        guard restorationStore.save(context) else {
            lastError = L10n.tr("Could not preserve the restoration record. Check the pairing file and tunnel IP before starting.")
            return false
        }
        restoreContext = context
        restorationRequired = true
        return true
    }

    private func clearRestoreMarker() {
        restoreContext = nil
        restorationRequired = false
        restorationStore.clear()
    }


    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: pinSource
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.coordinateKey == place.coordinateKey }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        if var previous = favorites.first(where: { $0.coordinateKey == place.coordinateKey }) {
            previous.name = place.name
            place = previous
        }
        favorites.removeAll { $0.coordinateKey == place.coordinateKey }
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
        if let favorite = favorites.first(where: { $0.coordinateKey == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).coordinateKey }),
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
    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool, token: Int, allowRetry: Bool = true) async -> Bool {
        guard !Task.isCancelled, operationEpoch.accepts(token), canWrite else { return false }
        let startFix = simulated == nil && latestFix?.isSimulated == false ? latestFix : nil
        let previousStatus = status
        if status == .idle { status = .connecting }
        else if status.isDropped { status = .reconnecting }
        isBusy = true
        let alreadyHadRestoreMarker = restorationRequired
        guard markRestoreNeeded(coordinate, pairing: pairing) else {
            isBusy = false
            status = previousStatus
            return false
        }
        let result = await transport.set(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                              pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
        guard operationEpoch.accepts(token), !isStopping else { return false }
        isBusy = false
        switch result {
        case .success:
            if simulated == nil {
                simulationStartFix = startFix
                restoredFix = nil
            }
            simulated = coordinate
            status = .active
            lastError = nil
            lastNotifiedDropReason = nil
            locationKeeper.setSimulationActive(true)
            if backgroundEnabled { beginBackground() }
            startResend(pairing: pairing)
            if markRecent { pushRecent(coordinate) }
            return true
        case .failure(let error):
            if !alreadyHadRestoreMarker {
                switch error {
                case .invalidCoordinate, .invalidIP, .pairingRead, .tunnelCreate, .remoteServer, .simulationCreate, .operationBusy, .operationCancelled, .serviceUnreachable, .localNetworkDenied:
                    clearRestoreMarker()
                default: break
                }
            }
            lastError = error.localizedDescription
            if simulated != nil || restorationRequired {
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else { status = .idle }
            stopJoystick()
            if allowRetry { scheduleRetries(pairing: pairing, token: token) }
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore, token: Int) async {
        guard joystickActive, canWrite, let current = simulated else { return }
        let now = clock.now
        let elapsed = now - lastJoystickTick
        lastJoystickTick = now
        guard elapsed <= RoutePlaybackCore.stallLimit else {
            stopJoystick()
            lastError = L10n.tr("Joystick stopped after an execution delay. Enable it again when ready.")
            return
        }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let speed = travelMode.baseSpeed * min(1.0, magnitude) * Double.random(in: 0.9...1.1)
        let meters = speed * max(0, elapsed)
        let next = offset(coordinate: current, eastMeters: joystickVector.dx / magnitude * meters,
                          northMeters: -joystickVector.dy / magnitude * meters)
        await apply(next, pairing: pairing, markRecent: false, token: token)
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.canWrite, self.routeTask == nil, self.retryTask == nil,
                      let simulated = self.simulated else { return }
                await self.apply(simulated, pairing: pairing, markRecent: false, token: self.generation)
            }
        }
    }

    private func scheduleRetries(pairing: PairingStore, token: Int) {
        guard retryTask == nil, simulated != nil, !isStopping else { return }
        let runToken = retryEpoch.invalidate()
        retryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if retryEpoch.accepts(runToken) {
                    retryTask = nil
                }
            }
            var schedule = RetrySchedule()
            while let delay = schedule.nextDelay() {
                do { try await clock.sleep(until: clock.now + delay) } catch { schedule.cancel(); return }
                guard retryEpoch.accepts(runToken), operationEpoch.accepts(token), !isStopping, let coordinate = simulated else { return }
                guard canWrite else { continue }
                if await apply(coordinate, pairing: pairing, markRecent: false, token: token, allowRetry: false) { return }
            }
            guard operationEpoch.accepts(token) else { return }
            stopResend()
        }
    }

    private func cancelRetries() {
        retryEpoch.invalidate()
        retryTask?.cancel()
        retryTask = nil
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
        cancelRetries()
        networkValidationTask?.cancel()
        networkValidationTask = nil
    }

    private func networkPathChanged(signature: String, available: Bool) {
        guard lastNetworkSignature != signature else { return }
        lastNetworkSignature = signature
        guard simulated != nil, !isStopping else { return }
        if !available, routeState == .playing { pauseRoute(reason: .transportInterrupted) }
        networkValidationTask?.cancel()
        networkValidationTask = Task { [weak self] in
            guard let self else { return }
            do { try await clock.sleep(until: clock.now + 0.5) } catch { return }
            validateConnection()
        }
    }

    private func validateConnection() {
        // Route writes already validate the live connection; never disrupt one
        // merely because NWPathMonitor reported a network interface change.
        guard canWrite, routeTask == nil, let pairing = activePairing, simulated != nil else { return }
        let token = generation
        Task {
            guard operationEpoch.accepts(token), canWrite, routeTask == nil else { return }
            isBusy = true
            let result = await transport.validateConnection(pairingPath: pairing.pairingPath, deviceIP: TunnelConfig.targetIP)
            guard operationEpoch.accepts(token), !isStopping else { return }
            isBusy = false
            if case .failure(let error) = result {
                lastError = error.localizedDescription
                status = .dropped(error.localizedDescription)
                if routeCore != nil { routeCore?.pause(.transportInterrupted); publishRoute() }
                stopJoystick()
                postDropNotification(error.localizedDescription)
                scheduleRetries(pairing: pairing, token: token)
            }
            // Reachable confirms the service endpoint, not the DVT socket or GPS.
            // A normal heartbeat/route write checks the native session next.
        }
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(name: Self.coordinateLabel(coordinate), coordinate: coordinate)
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var place = SavedPlace(name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
                               latitude: coordinate.latitude, longitude: coordinate.longitude, source: pinSource)
        if let previous = recents.first(where: { $0.coordinateKey == place.coordinateKey }) { place.id = previous.id }
        recents.removeAll { abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015 }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    func correctFavoriteFromGCJ02(_ place: SavedPlace) {
        guard let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        do {
            favorites[index] = try favorites[index].correctedFromGCJ02()
            SavedPlace.save(favorites, key: favoritesKey)
        } catch { lastError = error.localizedDescription }
    }

    func restoreFavoriteOriginalCoordinate(_ place: SavedPlace) {
        guard let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index] = favorites[index].restoringOriginalCoordinate()
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func correctRecentFromGCJ02(_ place: SavedPlace) {
        guard let index = recents.firstIndex(where: { $0.id == place.id }) else { return }
        do {
            recents[index] = try recents[index].correctedFromGCJ02()
            SavedPlace.save(recents, key: recentsKey)
        } catch { lastError = error.localizedDescription }
    }

    func restoreRecentOriginalCoordinate(_ place: SavedPlace) {
        guard let index = recents.firstIndex(where: { $0.id == place.id }) else { return }
        recents[index] = recents[index].restoringOriginalCoordinate()
        SavedPlace.save(recents, key: recentsKey)
    }

    func reloadPlaces() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in
                self?.pauseRoute(reason: .executionInterrupted)
                self?.stopJoystick()
                self?.endBackground()
            }
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        guard lastNotifiedDropReason != message else { return }
        lastNotifiedDropReason = message
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.tr("Locus spoof dropped")
            content.body = message
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "locus.connection.interrupted", content: content, trigger: nil))
        }
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * max(0.000001, cos(coordinate.latitude * .pi / 180))) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: min(90, max(-90, coordinate.latitude + dLat)),
                                      longitude: RouteGeometry.wrapLongitude(coordinate.longitude + dLon))
    }
}
