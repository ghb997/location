import Foundation
import Network

/// Public-facing pairable-host listener.
///
/// Uses Network.framework `NWListener` + Bonjour (what iOS 27 Developer Mode
/// browses). Inbound connections are relayed to the Rust pairable-host on
/// 127.0.0.1 so accept() still completes while Settings is in the foreground.
@MainActor
final class PairableHostAdvertiser {
    var onFailure: ((String) -> Void)?
    private var listener: NWListener?
    private var activeRelay: RelayPipe?
    private var activeRelayID: UUID?
    private(set) var publishedPort: UInt16 = 0
    private var rustLoopbackPort: UInt16 = 0
    private var generation = 0

    func publish(
        port: UInt16,
        serviceIdentifier: String,
        name: String,
        model: String,
        authTag: String,
        ver: String,
        minVer: String
    ) {
        stop()
        let token = generation
        rustLoopbackPort = port

        var txt = NWTXTRecord()
        txt["name"] = name
        txt["identifier"] = serviceIdentifier
        txt["authTag"] = authTag
        txt["model"] = model
        txt["flags"] = "1"
        txt["ver"] = ver
        txt["minVer"] = minVer

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true

            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: serviceIdentifier,
                type: "_remotepairing-pairable-host._tcp",
                domain: "local",
                txtRecord: txt
            )

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    switch state {
                    case .ready: self.publishedPort = listener.port?.rawValue ?? 0
                    case .failed(let error): self.onFailure?(error.localizedDescription)
                    default: break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { connection.cancel(); return }
                    self.relay(connection)
                }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            onFailure?(error.localizedDescription)
        }
    }

    func stop() {
        generation += 1
        activeRelay?.cancel()
        activeRelay = nil
        activeRelayID = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        publishedPort = 0
    }

    private func relay(_ inbound: NWConnection) {
        activeRelay?.cancel()
        activeRelay = nil
        activeRelayID = nil
        let rustPort = rustLoopbackPort
        guard rustPort > 0, let nwPort = NWEndpoint.Port(rawValue: rustPort) else {
            inbound.cancel()
            onFailure?(L10n.tr("The native pairing listener returned an invalid port."))
            return
        }

        let outbound = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: nwPort,
            using: .tcp
        )
        let token = generation
        let relayID = UUID()
        let pipe = RelayPipe(inbound: inbound, outbound: outbound) { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.activeRelayID == relayID else { return }
                self.onFailure?(message)
            }
        }
        activeRelay = pipe
        activeRelayID = relayID
        pipe.start()
    }
}

/// Bidirectional byte pump between Developer Mode and the Rust loopback listener.
private final class RelayPipe {
    private let inbound: NWConnection
    private let outbound: NWConnection
    private let queue = DispatchQueue(label: "locus.pairable.relay")
    private let onFailure: (String) -> Void
    private var cancelled = false

    init(inbound: NWConnection, outbound: NWConnection, onFailure: @escaping (String) -> Void) {
        self.inbound = inbound
        self.outbound = outbound
        self.onFailure = onFailure
    }

    func start() {
        inbound.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.fail(error) }
            if case .cancelled = state { self?.cancel() }
        }
        outbound.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                NSLog("[Locus] relay connected to Rust loopback")
                self.pump(from: self.inbound, to: self.outbound)
                self.pump(from: self.outbound, to: self.inbound)
            case .failed(let error):
                NSLog("[Locus] relay to Rust failed: %@", String(describing: error))
                self.fail(error)
            case .cancelled:
                self.cancel()
            default:
                break
            }
        }
        inbound.start(queue: queue)
        outbound.start(queue: queue)
    }

    func cancel() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        guard !cancelled else { return }
        cancelled = true
        inbound.stateUpdateHandler = nil
        outbound.stateUpdateHandler = nil
        inbound.cancel()
        outbound.cancel()
    }

    private func fail(_ error: NWError) {
        guard !cancelled else { return }
        stopOnQueue()
        onFailure(error.localizedDescription)
    }

    private func pump(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.cancelled else { return }
            if let error {
                NSLog("[Locus] relay receive error: %@", String(describing: error))
                self.fail(error)
                return
            }
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError {
                        NSLog("[Locus] relay send error: %@", String(describing: sendError))
                        self.fail(sendError)
                        return
                    }
                    if isComplete {
                        self.cancel()
                    } else {
                        self.pump(from: from, to: to)
                    }
                })
            } else if isComplete {
                self.cancel()
            } else {
                self.pump(from: from, to: to)
            }
        }
    }
}
