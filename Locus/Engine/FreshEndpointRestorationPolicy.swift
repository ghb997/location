import Foundation

enum ExistingRestorationResult<Target, Failure: Error> {
    case restored
    case reconnect(Target)
    case failed(Failure)
}

/// The transport exposes no coordinate write. An existing handle gets the
/// first clear attempt; a failed clear must discover and probe a fresh endpoint
/// before the one permitted reconnect. The caller owns its stop reservation
/// across every suspension, including a late return after its UI watchdog.
@MainActor
protocol FreshEndpointRestorationTransport {
    associatedtype Target
    associatedtype Failure: Error
    func clearExisting() async -> ExistingRestorationResult<Target, Failure>
    func resolveEndpoint(for target: Target) async -> Result<TunnelEndpoint, Failure>
    func connect(target: Target, endpoint: TunnelEndpoint) async -> Result<Void, Failure>
    func clearAndDisconnect() async -> Result<Void, Failure>
}

@MainActor
enum FreshEndpointRestorationPolicy {
    static func restore<T: FreshEndpointRestorationTransport>(_ transport: T) async -> Result<Void, T.Failure> {
        let target: T.Target
        switch await transport.clearExisting() {
        case .restored: return .success(())
        case .failed(let error): return .failure(error)
        case .reconnect(let value): target = value
        }
        let endpoint: TunnelEndpoint
        switch await transport.resolveEndpoint(for: target) {
        case .success(let value): endpoint = value
        case .failure(let error): return .failure(error)
        }
        if case .failure(let error) = await transport.connect(target: target, endpoint: endpoint) {
            return .failure(error)
        }
        return await transport.clearAndDisconnect()
    }
}
