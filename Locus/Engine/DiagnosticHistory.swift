import Foundation

/// Only allowlisted values enter this buffer. Native messages, endpoint IPs,
/// pairing paths, device identifiers and coordinates are never stored here.
struct DiagnosticHistory {
    enum Outcome: String { case started, stage, reachable, succeeded, failed, timedOut, lateCompletion }
    enum NetworkCategory: String {
        case cancelled, probeTimeout, unreachable, localNetworkDenied, unknown

        init(_ error: Error) {
            if error is CancellationError { self = .cancelled; return }
            switch error as? TunnelNetworkError {
            case .cancelled: self = .cancelled
            case .probeTimeout: self = .probeTimeout
            case .unreachable: self = .unreachable
            case .localNetworkDenied: self = .localNetworkDenied
            case nil: self = .unknown
            }
        }
    }

    struct Entry {
        let sequence: Int
        let operation: Int
        let timestamp: Date
        let elapsed: TimeInterval
        let stage: TunnelStage
        let outcome: Outcome
        let source: TunnelEndpoint.Source?
        let port: UInt16?
        let error: LocationEngineError?
        let network: NetworkCategory?
        let nativeCode: Int32?
        let nativeSubcode: Int32?

        var isFailure: Bool { error != nil || network != nil || outcome == .failed || outcome == .timedOut }

        var exportLine: String {
            let date = ISO8601DateFormatter().string(from: timestamp)
            var fields = ["#\(sequence)", date, "operation=\(operation)", "stage=\(stage.rawValue)",
                          "event=\(outcome.rawValue)", "elapsed=\(String(format: "%.2f", elapsed))s"]
            if let source { fields.append("source=\(source.rawValue)") }
            if let port { fields.append("port=\(port)") }
            if let error { fields.append("error=\(String(describing: error))") }
            if let network { fields.append("network=\(network.rawValue)") }
            if let nativeCode, let nativeSubcode { fields.append("native=\(nativeCode)/\(nativeSubcode)") }
            return fields.joined(separator: " ")
        }
    }

    private(set) var entries: [Entry] = []
    private(set) var recentFailures: [Entry] = []
    private var nextSequence = 0
    private let capacity: Int
    private let failureCapacity: Int

    init(capacity: Int = 80, failureCapacity: Int = 12) {
        self.capacity = max(1, capacity)
        self.failureCapacity = max(1, failureCapacity)
    }

    mutating func append(operation: Int, timestamp: Date = Date(), elapsed: TimeInterval,
                         stage: TunnelStage, outcome: Outcome, endpoint: TunnelEndpoint? = nil,
                         error: LocationEngineError? = nil, network: NetworkCategory? = nil,
                         native: NativeTunnelError? = nil) {
        nextSequence += 1
        let entry = Entry(sequence: nextSequence, operation: operation, timestamp: timestamp,
                          elapsed: elapsed.isFinite ? max(0, elapsed) : 0, stage: stage, outcome: outcome,
                          source: endpoint?.source, port: endpoint?.port, error: error, network: network,
                          nativeCode: native?.code, nativeSubcode: native?.subcode)
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        if entry.isFailure {
            recentFailures.append(entry)
            if recentFailures.count > failureCapacity { recentFailures.removeFirst(recentFailures.count - failureCapacity) }
        }
    }

    var exportText: String {
        "Recent connection events (oldest first):\n" + entries.map(\.exportLine).joined(separator: "\n")
            + "\nRetained recent failures (also retained after successful heartbeats):\n"
            + recentFailures.map(\.exportLine).joined(separator: "\n")
            + "\nAddresses, paths, pairing identifiers, PINs, coordinates and native messages omitted."
    }
}
