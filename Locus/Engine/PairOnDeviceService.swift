import Foundation
import Combine
import idevice
import UIKit
import UserNotifications
import CoreLocation

/// Shared by setup and settings. The native accept call has no cancellation
/// handle, so a cancelled run remains busy until its worker actually returns.
@MainActor
final class PairOnDeviceService: ObservableObject {
    enum Phase: Equatable {
        case idle, advertising, deviceConnected, awaitingPIN(String), succeeded, failed(String)
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pin: String?
    @Published private(set) var debugPort: UInt16?
    @Published private(set) var isWorkerRunning = false
    var isBusy: Bool { isWorkerRunning }
    private var run: PairRunContext?
    private let attempt = PairingAttemptPolicy()
    private var deadline: Task<Void, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let keepAlive = PairingKeepAlive()
    private let audioKeepAlive = SilentAudioKeepAlive()
    private let advertiser = PairableHostAdvertiser()

    func start(pairingStore: PairingStore) {
        guard !isWorkerRunning else { return }
        let temporaryURL: URL
        do { temporaryURL = try pairingStore.makeTemporaryPairingURL() }
        catch { phase = .failed(L10n.tr("Could not create a protected temporary pairing file.")); return }
        guard let id = attempt.begin() else { try? FileManager.default.removeItem(at: temporaryURL); return }
        let context = PairRunContext(id: id, temporaryURL: temporaryURL, owner: self)
        run = context
        isWorkerRunning = true
        phase = .advertising
        pin = nil
        debugPort = nil
        advertiser.onFailure = { [weak self] message in
            guard let self, self.accepts(context) else { return }
            self.cancel(message: L10n.tr("The pairing connection failed. Check Local Network permission and try again after the native listener finishes.") + " " + message)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        beginKeepAlive()
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) }
            catch { return }
            guard let self, self.accepts(context) else { return }
            self.cancel(message: L10n.tr("Pairing timed out after two minutes. The native listener is still finishing; retry is unavailable until it returns."))
        }
        let worker = Thread {
            let result = Self.runBlockingAccept(context: context)
            DispatchQueue.main.async {
                context.owner?.workerFinished(context: context, result: result, pairingStore: pairingStore)
            }
        }
        worker.name = "locus.pairable-host"
        worker.qualityOfService = .userInitiated
        worker.start()
    }

    func acknowledgeFailure() {
        guard !isWorkerRunning else { return }
        if case .failed = phase { teardown(); phase = .idle; pin = nil }
    }

    func cancel() {
        cancel(message: L10n.tr("Pairing cancelled. The native listener is still finishing; retry is unavailable until it returns."))
    }

    private func cancel(message: String) {
        guard isWorkerRunning else { return }
        if let run { attempt.cancel(id: run.id) }
        run?.cancel()
        pin = nil
        phase = .failed(message)
        teardown()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["locus.pairing.pin"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["locus.pairing.pin"])
    }

    func resetToIdle() {
        if isWorkerRunning { cancel(); return }
        teardown(); phase = .idle; pin = nil; debugPort = nil
    }

    fileprivate func accepts(_ context: PairRunContext) -> Bool {
        attempt.acceptsCallbacks(id: context.id) && !context.isCancelled
    }

    fileprivate func handleListening(context: PairRunContext, port: UInt16, values: [String]) {
        guard accepts(context) else { return }
        debugPort = port
        advertiser.publish(port: port, serviceIdentifier: values[0], name: values[1], model: values[2],
                           authTag: values[3], ver: values[4], minVer: values[5])
        guard accepts(context) else { return }
        phase = .advertising
    }

    fileprivate func handleConnected(context: PairRunContext) {
        guard accepts(context) else { return }
        phase = .deviceConnected
        Self.postNotification(title: L10n.tr("Locus connected"), body: L10n.tr("Generating pairing code…"))
    }

    fileprivate func handlePIN(context: PairRunContext, value: String) {
        guard accepts(context) else { return }
        pin = value
        phase = .awaitingPIN(value)
        Self.postNotification(title: L10n.tr("Locus pairing code"), body: value, identifier: "locus.pairing.pin")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func workerFinished(context: PairRunContext, result: Result<Void, PairRunError>, pairingStore: PairingStore) {
        defer { try? FileManager.default.removeItem(at: context.temporaryURL) }
        let disposition = attempt.finish(id: context.id)
        guard disposition != .ignored else { return }
        let cancelled = disposition == .cancelled || context.isCancelled
        isWorkerRunning = false
        run = nil
        teardown()
        pin = nil
        if cancelled {
            phase = .failed(L10n.tr("Pairing cancelled. The native listener has finished; you can try again."))
            return
        }
        switch result {
        case .failure(let error): phase = .failed(error.message)
        case .success:
            do {
                try pairingStore.installCompletedPairing(from: context.temporaryURL)
                phase = .succeeded
                Self.postNotification(title: L10n.tr("Locus paired"), body: L10n.tr("RPPairing is ready. Connect LocalDevVPN, then teleport."))
            } catch {
                phase = .failed(L10n.tr("Paired, but the pairing file could not be validated or saved. Your previous pairing is unchanged."))
            }
        }
    }

    private func teardown() {
        deadline?.cancel(); deadline = nil
        advertiser.stop()
        advertiser.onFailure = nil
        endKeepAlive()
    }

    private func beginKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = true
        keepAlive.start()
        audioKeepAlive.start()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "locus.pairable-host") { [weak self] in
            Task { @MainActor in self?.endKeepAlive() }
        }
    }

    private func endKeepAlive() {
        UIApplication.shared.isIdleTimerDisabled = false
        keepAlive.stop(); audioKeepAlive.stop()
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private static func postNotification(title: String, body: String, identifier: String = "locus.pairing.status") {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated private static func runBlockingAccept(context: PairRunContext) -> Result<Void, PairRunError> {
        LocationEngine.configureNativeTimeout()
        var outFile: OpaquePointer?
        var altIRK = [UInt8](repeating: 0, count: 16)
        let opaque = Unmanaged.passUnretained(context).toOpaque()
        let error = pairable_host_accept("Locus", "Mac17,7", 0, pinDisplayTrampoline, opaque,
            listeningTrampoline, opaque, connectedTrampoline, opaque, &altIRK, &outFile)
        defer { if let outFile { rp_pairing_file_free(outFile) } }
        if let error { return .failure(copyAndFree(error)) }
        guard !context.isCancelled else { return .failure(PairRunError(message: "Cancelled")) }
        guard let outFile else { return .failure(PairRunError(message: L10n.tr("Pairing finished but no pairing file was returned."))) }
        // Native workers know only their unique temporary path. The shared host
        // verifies the run again on MainActor before installing the final file.
        if let error = context.temporaryURL.path.withCString({ rp_pairing_file_write(outFile, $0) }) {
            return .failure(copyAndFree(error))
        }
        return .success(())
    }

    nonisolated private static func copyAndFree(_ error: UnsafeMutablePointer<IdeviceFfiError>) -> PairRunError {
        let message = error.pointee.message.map { String(cString: $0) }
            ?? L10n.format("Unknown pairing error (%d)", error.pointee.code)
        idevice_error_free(error)
        return PairRunError(message: message)
    }
}

private struct PairRunError: Error { let message: String }

fileprivate final class PairRunContext: @unchecked Sendable {
    let id: UUID
    let temporaryURL: URL
    weak var owner: PairOnDeviceService?
    private let lock = NSLock()
    private var cancelled = false
    init(id: UUID, temporaryURL: URL, owner: PairOnDeviceService) {
        self.id = id; self.temporaryURL = temporaryURL; self.owner = owner
    }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

@MainActor
private final class PairingKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isActive = false
    private var preferencesObserver: NSObjectProtocol?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.configureUpdates() }
        }
    }
    deinit {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
    }
    func start() {
        isActive = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        configureUpdates()
    }
    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
    }
    private func configureUpdates() {
        let authorization = manager.authorizationStatus
        let allowed = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        let background = isActive && UserDefaults.standard.bool(forKey: "locus.backgroundEnabled")
            && authorization == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.pausesLocationUpdatesAutomatically = !background
        if isActive && allowed { manager.startUpdatingLocation() }
        else { manager.stopUpdatingLocation() }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.configureUpdates() }
    }
}

private func pinDisplayTrampoline(pin: UnsafePointer<CChar>?, context: UnsafeMutableRawPointer?) {
    guard let pin, let context else { return }
    let run = Unmanaged<PairRunContext>.fromOpaque(context).takeUnretainedValue()
    let value = String(cString: pin)
    DispatchQueue.main.async { run.owner?.handlePIN(context: run, value: value) }
}

private func listeningTrampoline(port: UInt16, serviceIdentifier: UnsafePointer<CChar>?, name: UnsafePointer<CChar>?,
    model: UnsafePointer<CChar>?, authTag: UnsafePointer<CChar>?, ver: UnsafePointer<CChar>?, minVer: UnsafePointer<CChar>?,
    context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let run = Unmanaged<PairRunContext>.fromOpaque(context).takeUnretainedValue()
    let values = [serviceIdentifier, name, model, authTag, ver, minVer].map { $0.map { String(cString: $0) } ?? "" }
    DispatchQueue.main.async { run.owner?.handleListening(context: run, port: port, values: values) }
}

private func connectedTrampoline(context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let run = Unmanaged<PairRunContext>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { run.owner?.handleConnected(context: run) }
}
