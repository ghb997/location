import Foundation

enum TunnelNetworkError: Error { case cancelled, probeTimeout, unreachable, localNetworkDenied }

@MainActor
protocol TunnelNetworkPreparing {
    func discover(targetIP: String) async throws -> TunnelEndpoint?
    func probe(_ endpoint: TunnelEndpoint) async throws
}

@MainActor
enum TunnelPreparationPolicy {
    static func prepare<T: TunnelNetworkPreparing>(targetIP: String, automatic: Bool, manualPort: UInt16,
        transport: T, onStage: ((TunnelStage, TunnelEndpoint?) -> Void)? = nil) async throws -> TunnelEndpoint {
        try Task.checkCancellation()
        if !automatic {
            let endpoint = TunnelEndpoint(ip: targetIP, port: manualPort, source: .manual)
            onStage?(.probe, endpoint)
            try await transport.probe(endpoint)
            try Task.checkCancellation()
            return endpoint
        }
        onStage?(.discovery, nil)
        let discovered = try await transport.discover(targetIP: targetIP)
        try Task.checkCancellation()
        if let discovered {
            do {
                onStage?(.probe, discovered)
                try await transport.probe(discovered)
                try Task.checkCancellation()
                return discovered
            } catch is CancellationError { throw CancellationError() }
            catch TunnelNetworkError.cancelled { throw CancellationError() }
            catch TunnelNetworkError.localNetworkDenied { throw TunnelNetworkError.localNetworkDenied }
            catch {
                // Never retry an identical endpoint or reinterpret cancellation
                // or denied permission as an invitation to open more sockets.
                if discovered.port == TunnelPolicy.fallbackPort { throw error }
            }
        }
        try Task.checkCancellation()
        let fallback = TunnelEndpoint(ip: targetIP, port: TunnelPolicy.fallbackPort, source: .fallback)
        onStage?(.probe, fallback)
        try await transport.probe(fallback)
        try Task.checkCancellation()
        return fallback
    }
}
