import Foundation

@MainActor
final class NativeOperationGate {
    enum Kind: Equatable { case write, clear }
    private(set) var pending: [(id: UUID, kind: Kind)] = []
    private var expired = Set<UUID>()
    private(set) var stopReserved = false
    var isDraining: Bool { !expired.isEmpty }
    var canWrite: Bool { !stopReserved && !isDraining && pending.isEmpty }
    var count: Int { pending.count }

    func reserveStop() -> Bool {
        guard !stopReserved else { return false }
        stopReserved = true
        return true
    }
    func releaseStopPreparation() { stopReserved = false }
    func submit(id: UUID, kind: Kind) { pending.append((id, kind)) }
    func timeOut(id: UUID) {
        if pending.contains(where: { $0.id == id }) { expired.insert(id) }
    }
    func complete(id: UUID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            if pending[index].kind == .clear { stopReserved = false }
            pending.remove(at: index)
        }
        expired.remove(id)
    }
}

/// The restoration interface deliberately has no location-writing operation.
/// Production and tests share the same retry/cleanup sequence.
protocol LocationRestorationTransport {
    associatedtype Failure: Error
    var hasConnection: Bool { get }
    var canReconnect: Bool { get }
    mutating func connect() -> Result<Void, Failure>
    mutating func clear() -> Result<Void, Failure>
    mutating func disconnect()
}

enum LocationRestorationPolicy {
    static func restore<T: LocationRestorationTransport>(_ transport: inout T) -> Result<Void, T.Failure> {
        if transport.hasConnection {
            let result = transport.clear()
            transport.disconnect()
            if case .success = result { return result }
            if !transport.canReconnect { return result }
        }
        guard transport.canReconnect else { return .success(()) }
        let connection = transport.connect()
        if case .failure = connection { transport.disconnect(); return connection }
        let result = transport.clear()
        transport.disconnect()
        return result
    }
}
