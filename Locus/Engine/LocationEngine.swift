import Foundation
import idevice

private struct LocationConnectionContext: Equatable, Sendable {
    let pairingPath: String
    let endpoint: TunnelEndpoint
}

private struct LocationRestoreTarget: Sendable {
    let pairingPath: String
    let deviceIP: String
    init(_ context: LocationConnectionContext) {
        pairingPath = context.pairingPath
        deviceIP = context.endpoint.ip
    }
    init(pairingPath: String, deviceIP: String) {
        self.pairingPath = pairingPath
        self.deviceIP = deviceIP
    }
}

private struct NativeLocationResult: Error {
    let error: LocationEngineError?
    let native: NativeTunnelError?
    static let success = NativeLocationResult(error: nil, native: nil)
}

/// A UI watchdog never frees an in-flight handle or starts another worker.
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.ghb997.location.native", qos: .userInitiated)
    private static let configuredTimeout: Void = idevice_set_global_timeout(TunnelPolicy.nativeTimeoutSeconds)
    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?
    private static var nativeContext: LocationConnectionContext?
    private static var lastApplied: LocationConnectionContext?
    @MainActor private static var activeContext: LocationConnectionContext?
    @MainActor private static var preparation: Task<TunnelEndpoint, Error>?
    @MainActor private static var preparationID: UUID?
    @MainActor private static var preparationGeneration = 0
    @MainActor private static let gate = NativeOperationGate()
    @MainActor private static var submittedContext: LocationConnectionContext?
    @MainActor private static var writeControl: NativeRequestControl?

    @MainActor static var isStopPending: Bool { gate.stopReserved }

    static func configureNativeTimeout() { _ = configuredTimeout }

    /// Checks the service endpoint, not locationd's current coordinates. This
    /// path never allocates, clears or invalidates native simulation handles.
    @MainActor
    static func validateConnection(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        guard gate.canWrite, preparation == nil else { return .failure(.operationBusy) }
        guard TunnelConfig.isValidIP(deviceIP) else { return .failure(.invalidIP) }
        let token = preparationGeneration
        let id = TunnelDiagnostics.shared.begin(stage: .probe)
        let existing = activeContext.flatMap { $0.pairingPath == pairingPath && $0.endpoint.ip == deviceIP ? $0.endpoint : nil }
        let task = Task { @MainActor in
            if let existing {
                TunnelDiagnostics.shared.update(id: id, stage: .probe, endpoint: existing)
                try await TunnelPreparation.probe(existing)
                return existing
            }
            return try await TunnelPreparation.endpoint(deviceIP: deviceIP) { stage, endpoint in
                TunnelDiagnostics.shared.update(id: id, stage: stage, endpoint: endpoint)
            }
        }
        preparation = task
        preparationID = id
        defer { if preparationID == id { preparation = nil; preparationID = nil } }
        do {
            let endpoint = try await task.value
            guard token == preparationGeneration, !Task.isCancelled else {
                TunnelDiagnostics.shared.completed(id: id, error: .operationCancelled)
                return .failure(.operationCancelled)
            }
            TunnelDiagnostics.shared.serviceReachable(id: id, endpoint: endpoint)
            return .success(())
        } catch {
            TunnelDiagnostics.shared.networkFailed(id: id, error: error)
            let error = mapNetworkError(error)
            TunnelDiagnostics.shared.completed(id: id, error: error)
            return .failure(error)
        }
    }

    @MainActor
    static func validate(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        await validateConnection(pairingPath: pairingPath, deviceIP: deviceIP)
    }

    @MainActor
    static func cancelPendingPreparation() {
        preparationGeneration += 1
        writeControl?.cancel()
        preparation?.cancel()
        preparation = nil
        preparationID = nil
    }

    @MainActor
    static func invalidateConnectionForRecovery() -> Bool {
        guard gate.canWrite, preparation == nil, !TunnelDiagnostics.shared.isDraining else { return false }
        activeContext = nil
        submittedContext = nil
        // Native handles remain queue-owned. Restoration first clears the old
        // connection, then reconnects using freshly resolved repair settings.
        // lastApplied remains available until a successful clear.
        return true
    }

    @MainActor
    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return .failure(.invalidCoordinate) }
        guard TunnelConfig.isValidIP(deviceIP) else { return .failure(.invalidIP) }
        guard gate.canWrite, !TunnelDiagnostics.shared.isDraining, preparation == nil else { return .failure(.operationBusy) }
        let token = preparationGeneration
        let control = NativeRequestControl(seconds: TunnelPolicy.operationSeconds)
        writeControl = control
        let id = TunnelDiagnostics.shared.begin(stage: .discovery)
        let context: LocationConnectionContext
        do { context = try await prepare(pairingPath: pairingPath, deviceIP: deviceIP, diagnosticID: id) }
        catch {
            let result = mapNetworkError(error)
            TunnelDiagnostics.shared.networkFailed(id: id, error: error)
            TunnelDiagnostics.shared.completed(id: id, error: result)
            return .failure(result)
        }
        guard token == preparationGeneration, gate.canWrite, !Task.isCancelled else {
            TunnelDiagnostics.shared.completed(id: id, error: .operationCancelled)
            return .failure(.operationCancelled)
        }
        return await submit(id: id, context: context, control: control) {
            setLocked(latitude: latitude, longitude: longitude, context: context, id: id, control: control)
        }
    }

    @MainActor
    static func clear(pairingPath: String? = nil, deviceIP: String? = nil) async -> Result<Void, LocationEngineError> {
        guard gate.reserveStop() else { return .failure(.operationBusy) }
        cancelPendingPreparation()
        let control = NativeRequestControl(seconds: TunnelPolicy.operationSeconds, purpose: .restoration)
        let id = TunnelDiagnostics.shared.begin(stage: .clear)
        let cached = activeContext ?? (gate.count > 0 ? submittedContext : nil)
        let target: LocationRestoreTarget?
        if pairingPath != nil || deviceIP != nil {
            target = LocationRestoreTarget(pairingPath: pairingPath ?? "", deviceIP: deviceIP ?? "")
        } else {
            target = cached.map(LocationRestoreTarget.init)
        }
        return await submitRestoration(id: id, target: target, control: control)
    }

    /// One stop reservation spans native draining, discovery and the final
    /// clear. A UI timeout never starts a second worker or releases ownership.
    @MainActor
    private static func submitRestoration(id: UUID, target: LocationRestoreTarget?,
                                          control: NativeRequestControl) async -> Result<Void, LocationEngineError> {
        gate.submit(id: id, kind: .clear)
        return await withCheckedContinuation { continuation in
            let completion = OperationCompletion<Result<Void, LocationEngineError>>(continuation)
            let watchdog = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(control.remainingSeconds * 1e9)) }
                catch { return }
                if completion.finish(.failure(.operationTimedOut)) {
                    gate.timeOut(id: id)
                    TunnelDiagnostics.shared.timedOut(id: id)
                }
            }
            Task { @MainActor in
                let result = await FreshEndpointRestorationPolicy.restore(
                    NativeRestoreTransport(target: target, id: id, control: control))
                watchdog.cancel()
                gate.complete(id: id)
                activeContext = nil
                let failure: NativeLocationResult?
                switch result {
                case .success: submittedContext = nil; failure = nil
                case .failure(let error): failure = error
                }
                let delivered = completion.finish(failure?.error.map { .failure($0) } ?? .success(()))
                TunnelDiagnostics.shared.completed(id: id,
                    error: delivered ? failure?.error : .operationTimedOut, native: failure?.native)
            }
        }
    }

    @MainActor
    private static func onNativeQueue<Value>(_ work: @escaping () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                configureNativeTimeout()
                continuation.resume(returning: work())
            }
        }
    }

    @MainActor
    private static func prepare(pairingPath: String, deviceIP: String, diagnosticID: UUID) async throws -> LocationConnectionContext {
        if let activeContext, activeContext.pairingPath == pairingPath, activeContext.endpoint.ip == deviceIP { return activeContext }
        let task = Task { @MainActor in
            try await TunnelPreparation.endpoint(deviceIP: deviceIP) { stage, endpoint in
                TunnelDiagnostics.shared.update(id: diagnosticID, stage: stage, endpoint: endpoint)
            }
        }
        let id = UUID()
        preparationID = id
        preparation = task
        defer {
            if preparationID == id { preparation = nil; preparationID = nil }
        }
        let endpoint = try await task.value
        return LocationConnectionContext(pairingPath: pairingPath, endpoint: endpoint)
    }

    private static func mapNetworkError(_ error: Error) -> LocationEngineError {
        if error is CancellationError { return .operationCancelled }
        switch error as? TunnelNetworkError {
        case .cancelled: return .operationCancelled
        case .localNetworkDenied: return .localNetworkDenied
        default: return .serviceUnreachable
        }
    }

    @MainActor
    private static func submit(id: UUID, context: LocationConnectionContext?, isClear: Bool = false,
                               control: NativeRequestControl,
                               work: @escaping () -> NativeLocationResult) async -> Result<Void, LocationEngineError> {
        gate.submit(id: id, kind: isClear ? .clear : .write)
        if !isClear { submittedContext = context }
        return await withCheckedContinuation { continuation in
            let completion: OperationCompletion<Result<Void, LocationEngineError>> = OperationCompletion(continuation)
            let watchdog = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(control.remainingSeconds * 1e9)) }
                catch { return }
                if completion.finish(.failure(.operationTimedOut)) {
                    gate.timeOut(id: id)
                    TunnelDiagnostics.shared.timedOut(id: id)
                }
            }
            queue.async {
                configureNativeTimeout()
                let result = work()
                DispatchQueue.main.async {
                    watchdog.cancel()
                    gate.complete(id: id)
                    activeContext = result.error == nil && !isClear ? context : nil
                    if isClear, result.error == nil { submittedContext = nil }
                    let delivered = completion.finish(result.error.map { .failure($0) } ?? .success(()))
                    TunnelDiagnostics.shared.completed(id: id,
                        error: delivered ? result.error : .operationTimedOut, native: result.native)
                }
            }
        }
    }

    private static func report(_ stage: TunnelStage, id: UUID, endpoint: TunnelEndpoint? = nil) {
        DispatchQueue.main.async { TunnelDiagnostics.shared.update(id: id, stage: stage, endpoint: endpoint) }
    }

    private static func failure(_ pointer: UnsafeMutablePointer<IdeviceFfiError>, stage: TunnelStage,
                                error: LocationEngineError) -> NativeLocationResult {
        let raw = pointer.pointee
        let detail = NativeTunnelError(stage: stage, code: raw.code, subcode: raw.sub_code,
                                       message: raw.message.map { String(cString: $0) } ?? "")
        idevice_error_free(pointer)
        return NativeLocationResult(error: error, native: detail)
    }

    private static func cleanup() {
        if let locationSimulation { location_simulation_free(locationSimulation); self.locationSimulation = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
        nativeContext = nil
    }

    private static func cancelledResult(_ control: NativeRequestControl) -> NativeLocationResult? {
        guard !control.mayStartNextStage else { return nil }
        if control.hasExpired { return NativeLocationResult(error: .operationTimedOut, native: nil) }
        if control.isCancelled { return NativeLocationResult(error: .operationCancelled, native: nil) }
        return nil
    }

    private static func connectLocked(context: LocationConnectionContext, id: UUID, control: NativeRequestControl) -> NativeLocationResult {
        if let stopped = cancelledResult(control) { cleanup(); return stopped }
        if locationSimulation != nil, nativeContext == context { return .success }
        cleanup()
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(context.endpoint.port).bigEndian
        guard context.endpoint.ip.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return NativeLocationResult(error: .invalidIP, native: nil)
        }
        report(.pairing, id: id, endpoint: context.endpoint)
        var pairingHandle: OpaquePointer?
        defer { if let pairingHandle { rp_pairing_file_free(pairingHandle) } }
        if let error = context.pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            return failure(error, stage: .pairing, error: .pairingRead)
        }
        guard let pairingHandle else { return NativeLocationResult(error: .pairingRead, native: nil) }
        if let stopped = cancelledResult(control) { cleanup(); return stopped }
        report(.tunnel, id: id)
        let error = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride), "LocusLocation",
                                       pairingHandle, nil, nil, &adapter, &handshake)
            }
        }
        if let error { let result = failure(error, stage: .tunnel, error: .tunnelCreate); cleanup(); return result }
        if let stopped = cancelledResult(control) { cleanup(); return stopped }
        report(.handshake, id: id)
        if let error = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let result = failure(error, stage: .handshake, error: .remoteServer); cleanup(); return result
        }
        if let stopped = cancelledResult(control) { cleanup(); return stopped }
        report(.simulation, id: id)
        if let error = location_simulation_new(remoteServer, &locationSimulation) {
            let result = failure(error, stage: .simulation, error: .simulationCreate); cleanup(); return result
        }
        remoteServer = nil // simulation handle owns the remote server
        nativeContext = context
        return .success
    }

    private static func setLocked(latitude: Double, longitude: Double, context: LocationConnectionContext, id: UUID,
                                  control: NativeRequestControl) -> NativeLocationResult {
        if let stopped = cancelledResult(control) { return stopped }
        if let locationSimulation, nativeContext == context {
            report(.set, id: id, endpoint: context.endpoint)
            if let error = location_simulation_set(locationSimulation, latitude, longitude) {
                let result = failure(error, stage: .set, error: .locationSet)
                DispatchQueue.main.async {
                    TunnelDiagnostics.shared.recordFailure(id: id, error: .locationSet, native: result.native)
                }
                cleanup()
            } else { lastApplied = context; return .success }
        }
        let connected = connectLocked(context: context, id: id, control: control)
        guard connected.error == nil else { return connected }
        if let stopped = cancelledResult(control) { cleanup(); return stopped }
        report(.set, id: id)
        if let error = location_simulation_set(locationSimulation, latitude, longitude) {
            let result = failure(error, stage: .set, error: .locationSet)
            lastApplied = context // a failed response does not prove the write was ignored
            cleanup(); return result
        }
        lastApplied = context
        return .success
    }

    @MainActor
    private struct NativeRestoreTransport: FreshEndpointRestorationTransport {
        let target: LocationRestoreTarget?
        let id: UUID
        let control: NativeRequestControl

        func clearExisting() async -> ExistingRestorationResult<LocationRestoreTarget, NativeLocationResult> {
            await onNativeQueue {
                let recovery = target ?? lastApplied.map(LocationRestoreTarget.init)
                if let locationSimulation {
                    report(.clear, id: id, endpoint: nativeContext?.endpoint)
                    if let error = location_simulation_clear(locationSimulation) {
                        let result = failure(error, stage: .clear, error: .locationClear)
                        DispatchQueue.main.async {
                            TunnelDiagnostics.shared.recordFailure(id: id, error: .locationClear, native: result.native)
                        }
                        cleanup()
                        if let recovery { return .reconnect(recovery) }
                        return .failed(result)
                    }
                    cleanup()
                    lastApplied = nil
                    return .restored
                }
                cleanup()
                return recovery.map { .reconnect($0) } ?? .restored
            }
        }

        func resolveEndpoint(for target: LocationRestoreTarget) async -> Result<TunnelEndpoint, NativeLocationResult> {
            guard !target.pairingPath.isEmpty, FileManager.default.fileExists(atPath: target.pairingPath) else {
                return .failure(NativeLocationResult(error: .pairingRead, native: nil))
            }
            guard TunnelConfig.isValidIP(target.deviceIP) else {
                return .failure(NativeLocationResult(error: .invalidIP, native: nil))
            }
            do {
                // Deliberately bypass prepare's activeContext cache. This runs
                // after the old clear/cleanup, even if the old write ran late.
                let endpoint = try await TunnelPreparation.endpoint(deviceIP: target.deviceIP) { stage, endpoint in
                    TunnelDiagnostics.shared.update(id: id, stage: stage, endpoint: endpoint)
                }
                return .success(endpoint)
            } catch {
                TunnelDiagnostics.shared.networkFailed(id: id, error: error)
                return .failure(NativeLocationResult(error: mapNetworkError(error), native: nil))
            }
        }

        func connect(target: LocationRestoreTarget, endpoint: TunnelEndpoint) async -> Result<Void, NativeLocationResult> {
            await onNativeQueue {
                let context = LocationConnectionContext(pairingPath: target.pairingPath, endpoint: endpoint)
                let result = connectLocked(context: context, id: id, control: control)
                if result.error != nil { cleanup(); return .failure(result) }
                return .success(())
            }
        }

        func clearAndDisconnect() async -> Result<Void, NativeLocationResult> {
            await onNativeQueue {
                defer { cleanup() }
                if let stopped = cancelledResult(control) { return .failure(stopped) }
                report(.clear, id: id, endpoint: nativeContext?.endpoint)
                if let error = location_simulation_clear(locationSimulation) {
                    return .failure(failure(error, stage: .clear, error: .locationClear))
                }
                lastApplied = nil
                return .success(())
            }
        }
    }
}
