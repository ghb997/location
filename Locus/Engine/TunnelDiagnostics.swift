import Foundation
import Combine
import Network
import Darwin
import UIKit

@MainActor
final class TunnelDiagnostics: ObservableObject {
    enum State: Equatable { case unknown, checking, reachable, ready, failed, draining }
    static let shared = TunnelDiagnostics()
    @Published private(set) var state: State = .unknown
    @Published private(set) var stage: TunnelStage?
    @Published private(set) var endpoint: TunnelEndpoint?
    @Published private(set) var nativeError: NativeTunnelError?
    @Published private(set) var message: String?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var isDraining = false
    private var pendingNative = Set<UUID>()
    private var latestOperation: UUID?
    private var checkTask: Task<Void, Never>?
    private var checkID: UUID?
    private var startedAt: Date?
    private var stageStartedAt: Date?
    private struct Operation {
        let sequence: Int
        let started: TimeInterval
        var stage: TunnelStage
        var endpoint: TunnelEndpoint?
    }
    private var operations: [UUID: Operation] = [:]
    private var operationSequence = 0
    private var history = DiagnosticHistory()

    var statusLabel: String {
        switch state {
        case .unknown: return L10n.tr("Connection not checked")
        case .checking: return L10n.tr("Checking connection…")
        case .reachable: return L10n.tr("RemotePairing service reachable")
        case .ready: return L10n.tr("Developer service ready")
        case .failed: return L10n.tr("Connection check failed")
        case .draining: return L10n.tr("Native operation still finishing")
        }
    }

    func check() async {
        cancelCheck()
        guard !isDraining else { return }
        let id = begin(stage: .discovery)
        let task = Task { @MainActor in
            do {
                let result = try await TunnelPreparation.endpoint(deviceIP: TunnelConfig.targetIP) { stage, endpoint in
                    self.update(id: id, stage: stage, endpoint: endpoint)
                }
                guard !Task.isCancelled, latestOperation == id else { return }
                serviceReachable(id: id, endpoint: result)
            } catch {
                guard !Task.isCancelled, latestOperation == id else { return }
                networkFailed(id: id, error: error)
                operations.removeValue(forKey: id)
                state = .failed
                message = Self.networkMessage(error)
                checkedAt = Date()
            }
        }
        checkTask = task
        checkID = id
        await task.value
        if checkID == id { checkTask = nil; checkID = nil }
    }

    func cancelCheck() {
        checkTask?.cancel(); checkTask = nil
        if let checkID {
            record(id: checkID, outcome: .failed, error: .operationCancelled)
            operations.removeValue(forKey: checkID)
        }
        checkID = nil
    }

    func summaryForExport() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let elapsed = startedAt.map { String(format: "%.1f", (checkedAt ?? Date()).timeIntervalSince($0)) } ?? "0"
        let stageElapsed = stageStartedAt.map { String(format: "%.1f", (checkedAt ?? Date()).timeIntervalSince($0)) } ?? "0"
        return "App: \(version) (\(build))\nSystem: iOS \(UIDevice.current.systemVersion)\nElapsed seconds: \(elapsed)\nStage elapsed seconds: \(stageElapsed)\n"
            + TunnelPolicy.exportSummary(stage: stage, source: endpoint?.source, port: endpoint?.port,
                                         error: nativeError, draining: isDraining)
            + "\n\n" + history.exportText
    }

    @discardableResult
    func begin(stage: TunnelStage) -> UUID {
        cancelCheck()
        let id = UUID()
        operationSequence += 1
        operations[id] = Operation(sequence: operationSequence, started: ProcessInfo.processInfo.systemUptime,
                                   stage: stage, endpoint: nil)
        latestOperation = id
        startedAt = Date()
        stageStartedAt = startedAt
        checkedAt = nil
        self.stage = stage
        endpoint = nil
        nativeError = nil
        message = nil
        state = .checking
        record(id: id, outcome: .started)
        return id
    }

    func update(id: UUID, stage: TunnelStage, endpoint: TunnelEndpoint? = nil) {
        if var operation = operations[id] {
            let changed = operation.stage != stage || (endpoint != nil && operation.endpoint != endpoint)
            operation.stage = stage
            if let endpoint { operation.endpoint = endpoint }
            operations[id] = operation
            if changed { record(id: id, outcome: .stage) }
        }
        guard latestOperation == id else { return }
        if self.stage != stage { stageStartedAt = Date() }
        self.stage = stage
        if let endpoint { self.endpoint = endpoint }
    }

    func completed(id: UUID, error: LocationEngineError?, native: NativeTunnelError? = nil) {
        let wasLate = pendingNative.contains(id)
        record(id: id, outcome: wasLate ? .lateCompletion : (error == nil ? .succeeded : .failed), error: error, native: native)
        operations.removeValue(forKey: id)
        pendingNative.remove(id)
        isDraining = !pendingNative.isEmpty
        guard latestOperation == id else { return }
        checkedAt = Date()
        nativeError = native
        message = error == .operationTimedOut && !isDraining
            ? L10n.tr("The request timed out. The native worker has finished; retry or confirm location restoration.")
            : error?.localizedDescription
        state = isDraining ? .draining : (error == nil ? .ready : .failed)
    }

    func timedOut(id: UUID) {
        record(id: id, outcome: .timedOut, error: .operationTimedOut)
        pendingNative.insert(id)
        isDraining = true
        guard latestOperation == id else { return }
        state = .draining
        message = LocationEngineError.operationTimedOut.localizedDescription
    }

    func serviceReachable(id: UUID, endpoint: TunnelEndpoint) {
        if var operation = operations[id] {
            operation.endpoint = endpoint
            operations[id] = operation
        }
        record(id: id, outcome: .reachable)
        operations.removeValue(forKey: id)
        guard latestOperation == id else { return }
        self.endpoint = endpoint
        checkedAt = Date()
        state = .reachable
        message = nil
    }

    func networkFailed(id: UUID, error: Error) {
        record(id: id, outcome: .failed, network: DiagnosticHistory.NetworkCategory(error))
    }

    /// An operation may recover internally. Preserve the first failure even
    /// when a reconnect or the next heartbeat succeeds.
    func recordFailure(id: UUID, error: LocationEngineError, native: NativeTunnelError?) {
        record(id: id, outcome: .failed, error: error, native: native)
    }

    private func record(id: UUID, outcome: DiagnosticHistory.Outcome, error: LocationEngineError? = nil,
                        network: DiagnosticHistory.NetworkCategory? = nil, native: NativeTunnelError? = nil) {
        guard let operation = operations[id] else { return }
        history.append(operation: operation.sequence, elapsed: ProcessInfo.processInfo.systemUptime - operation.started,
                       stage: native?.stage ?? operation.stage, outcome: outcome, endpoint: operation.endpoint,
                       error: error, network: network, native: native)
    }

    static func networkMessage(_ error: Error) -> String {
        if error is CancellationError { return LocationEngineError.operationCancelled.localizedDescription }
        switch error as? TunnelNetworkError {
        case .cancelled: return LocationEngineError.operationCancelled.localizedDescription
        case .localNetworkDenied: return LocationEngineError.localNetworkDenied.localizedDescription
        default: return LocationEngineError.serviceUnreachable.localizedDescription
        }
    }
}

@MainActor
enum TunnelPreparation {
    static func probe(_ endpoint: TunnelEndpoint) async throws { try await TCPProbe.run(endpoint) }

    static func endpoint(deviceIP: String, onStage: ((TunnelStage, TunnelEndpoint?) -> Void)? = nil) async throws -> TunnelEndpoint {
        try await TunnelPreparationPolicy.prepare(targetIP: deviceIP, automatic: TunnelConfig.automaticPort,
            manualPort: TunnelConfig.port, transport: RuntimeNetworkPreparation(), onStage: onStage)
    }
}

@MainActor
private struct RuntimeNetworkPreparation: TunnelNetworkPreparing {
    func discover(targetIP: String) async throws -> TunnelEndpoint? {
        try await RemotePairingDiscovery(targetIP: targetIP).resolve()
    }
    func probe(_ endpoint: TunnelEndpoint) async throws { try await TCPProbe.run(endpoint) }
}

/// Resolve SRV records without opening unrelated devices' TCP services.
@MainActor
private final class RemotePairingDiscovery: NSObject, NetServiceDelegate {
    let targetIP: String
    private var browser: NWBrowser?
    private var services: [String: NetService] = [:]
    private var continuation: CheckedContinuation<TunnelEndpoint?, Error>?
    private var deadline: Task<Void, Never>?

    init(targetIP: String) { self.targetIP = targetIP }

    func resolve() async throws -> TunnelEndpoint? {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(.failure(CancellationError())); return }
                let browser = NWBrowser(for: .bonjour(type: "_remotepairing._tcp", domain: "local."), using: .tcp)
                self.browser = browser
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    DispatchQueue.main.async { self?.resolve(results) }
                }
                browser.stateUpdateHandler = { [weak self] state in
                    let error: NWError
                    switch state {
                    case .failed(let value), .waiting(let value): error = value
                    default: return
                    }
                    DispatchQueue.main.async {
                        if case .dns(let code) = error, code == -65570 {
                            self?.finish(.failure(TunnelNetworkError.localNetworkDenied))
                        } else if case .failed = state { self?.finish(.success(nil)) }
                    }
                }
                browser.start(queue: .main)
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(TunnelPolicy.discoverySeconds * 1e9)) }
                    catch { return }
                    self?.finish(.success(nil))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func resolve(_ results: Set<NWBrowser.Result>) {
        guard continuation != nil else { return }
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            let key = "\(name)|\(type)|\(domain)"
            guard services[key] == nil else { continue }
            let service = NetService(domain: domain, type: type, name: name)
            service.delegate = self
            services[key] = service
            service.resolve(withTimeout: TunnelPolicy.discoverySeconds)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        // Copy immutable values on the callback thread. The NetService instance
        // stays on that thread; only its Sendable snapshot crosses to MainActor.
        let port = sender.port
        let addressData = sender.addresses ?? []
        Task { @MainActor [weak self] in
            self?.resolvedAddress(port: port, addressData: addressData)
        }
    }

    private func resolvedAddress(port: Int, addressData: [Data]) {
        guard continuation != nil, (1...65535).contains(port) else { return }
        let addresses = addressData.compactMap { data -> String? in
            guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            return data.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                var address = sockaddr_in()
                memcpy(&address, base, MemoryLayout<sockaddr_in>.size)
                guard address.sin_family == sa_family_t(AF_INET) else { return nil }
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                return inet_ntop(AF_INET, &address.sin_addr, &text, socklen_t(text.count)).map { String(cString: $0) }
            }
        }
        guard TunnelPolicy.accepts(addresses: addresses, targetIP: targetIP,
                                   localAddresses: LocalDevVPN.ipv4InterfaceAddresses()) else { return }
        finish(.success(TunnelEndpoint(ip: targetIP, port: UInt16(port), source: .bonjour)))
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) { }

    private func finish(_ result: Result<TunnelEndpoint?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        browser?.cancel(); browser = nil
        for service in services.values { service.stop(); service.delegate = nil }
        services.removeAll()
        continuation.resume(with: result)
    }
}

@MainActor
private final class TCPProbe {
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?

    static func run(_ endpoint: TunnelEndpoint) async throws {
        let probe = TCPProbe()
        try await probe.run(endpoint)
    }

    private func run(_ endpoint: TunnelEndpoint) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(.failure(CancellationError())); return }
                let connection = NWConnection(host: NWEndpoint.Host(endpoint.ip),
                    port: NWEndpoint.Port(rawValue: endpoint.port)!, using: .tcp)
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    DispatchQueue.main.async {
                        switch state {
                        case .ready: self?.finish(.success(()))
                        case .failed(let error):
                            if case .dns(let code) = error, code == -65570 {
                                self?.finish(.failure(TunnelNetworkError.localNetworkDenied))
                            } else { self?.finish(.failure(TunnelNetworkError.unreachable)) }
                        case .waiting(let error):
                            if case .posix(let code) = error, code == .EPERM || code == .EACCES {
                                self?.finish(.failure(TunnelNetworkError.localNetworkDenied))
                            }
                        case .cancelled: self?.finish(.failure(CancellationError()))
                        default: break
                        }
                    }
                }
                connection.start(queue: .main)
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(TunnelPolicy.probeSeconds * 1e9)) }
                    catch { return }
                    self?.finish(.failure(TunnelNetworkError.probeTimeout))
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        continuation.resume(with: result)
    }
}
