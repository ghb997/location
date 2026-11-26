import Foundation

struct TunnelEndpoint: Equatable, Sendable {
    enum Source: String, Sendable { case manual, bonjour, fallback }
    let ip: String
    let port: UInt16
    let source: Source
}

enum TunnelStage: String, Sendable {
    case discovery, probe, pairing, tunnel, handshake, simulation, set, clear
}

struct NativeTunnelError: Equatable, Sendable {
    let stage: TunnelStage
    let code: Int32
    let subcode: Int32
    let message: String
}

enum TunnelPolicy {
    static let fallbackPort: UInt16 = 49152
    static let discoverySeconds: TimeInterval = 3
    static let probeSeconds: TimeInterval = 2
    static let nativeTimeoutSeconds: UInt64 = 15
    static let operationSeconds: TimeInterval = 30

    static func accepts(addresses: [String], targetIP: String, localAddresses: [String]) -> Bool {
        let allowed = Set(localAddresses + [targetIP])
        return addresses.contains { allowed.contains($0) }
    }

    static func hasVPNInterface(targetIP: String, routeSource: String?, interfaces: [(name: String, address: String)]) -> Bool {
        guard TunnelConfig.isValidIP(targetIP), let lastDot = targetIP.lastIndex(of: ".") else { return false }
        let tunnelInterfaces = interfaces.filter {
            $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") || $0.name.hasPrefix("ppp")
        }
        if let routeSource, interfaces.contains(where: { $0.address == routeSource }) {
            return tunnelInterfaces.contains { $0.address == routeSource }
        }
        // Older LocalDevVPN builds assign an address in the peer's /24 directly to the tunnel.
        let prefix = String(targetIP[...lastDot])
        return tunnelInterfaces.contains { $0.address.hasPrefix(prefix) }
    }

    /// Exports only bounded, non-sensitive stage and error information. Native
    /// messages may contain addresses, file paths or pairing identifiers.
    static func exportSummary(stage: TunnelStage?, source: TunnelEndpoint.Source?, port: UInt16?,
                              error: NativeTunnelError?, draining: Bool) -> String {
        var lines = ["location connection diagnostic", "Stage: \(stage?.rawValue ?? "none")",
                     "Source: \(source?.rawValue ?? "none")", "Port: \(port.map(String.init) ?? "none")",
                     "Native operation pending: \(draining)"]
        if let error {
            lines.append("Native error: \(error.code) / \(error.subcode)")
        }
        lines.append("Addresses, paths, pairing identifiers, PINs and native messages omitted.")
        return lines.joined(separator: "\n")
    }
}

/// A callback and its watchdog may race. Exactly one returns the user-facing
/// result; a late native callback still owns and cleans up its native resources.
final class OperationCompletion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

    @discardableResult
    func finish(_ result: Value) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: result)
        return pending != nil
    }
}
