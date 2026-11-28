import Combine
import Darwin
import Foundation
import NetworkExtension
import UIKit

enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let detectURL = URL(string: "localdevvpn://")!

    /// Starts the tunnel, then returns to Locus via `locus://`.
    static let enableURL = URL(string: "localdevvpn://enable?scheme=locus")!

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(detectURL)
    }

    /// The VPN interface can be on a different subnet from the configured peer.
    static var isConnected: Bool {
        let target = TunnelConfig.targetIP
        return TunnelPolicy.hasVPNInterface(targetIP: target, routeSource: routeSourceAddress(for: target),
                                            interfaces: ipv4Interfaces())
    }

    static func openInstalled() {
        UIApplication.shared.open(enableURL)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }

    /// Open LocalDevVPN to connect if installed; otherwise App Store.
    static func openOrInstall() {
        if isInstalled {
            openInstalled()
        } else {
            openAppStore()
        }
    }

    /// Ask the kernel which source it would use for this peer without sending a datagram.
    private static func routeSourceAddress(for target: String) -> String? {
        var peer = sockaddr_in()
        let size = MemoryLayout<sockaddr_in>.size
        peer.sin_len = UInt8(size)
        peer.sin_family = sa_family_t(AF_INET)
        peer.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, target, &peer.sin_addr) == 1 else { return nil }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let result = withUnsafePointer(to: &peer) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(size))
            }
        }
        guard result == 0 else { return nil }

        var source = sockaddr_in()
        var length = socklen_t(size)
        let status = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard status == 0, source.sin_addr.s_addr != 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &source.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }

    static func ipv4InterfaceAddresses() -> [String] {
        ipv4Interfaces().map { $0.address }
    }

    private static func ipv4Interfaces() -> [(name: String, address: String)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [(name: String, address: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               let name = interface.ifa_name,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let nameLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(
                    address,
                    nameLen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    results.append((String(cString: name), String(cString: host)))
                }
            }
            ptr = interface.ifa_next
        }
        return results
    }
}

/// Only manages this app's own configuration. Other tunnel apps remain usable
/// with the existing endpoint discovery and service diagnostics.
@MainActor
final class BuiltInVPN: ObservableObject {
    static let shared = BuiltInVPN()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    private var manager: NETunnelProviderManager?
    private var statusObserver: AnyCancellable?
    private var configurationObserver: AnyCancellable?
    private var revision = 0
    private var expectsConnection = false

    private init() {
        configurationObserver = NotificationCenter.default.publisher(for: .NEVPNConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
    }

    private var providerID: String? {
        Bundle.main.bundleIdentifier.map { $0 + ".TunnelProvider" }
    }

    private var configuredPeer: String? {
        (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["targetIP"] as? String
    }

    var isConnected: Bool { status == .connected }
    var canDisconnect: Bool { [.connected, .connecting, .reasserting].contains(status) }

    var isTransitioning: Bool {
        isSaving || [.connecting, .reasserting, .disconnecting].contains(status)
    }

    var matchesEndpoint: Bool {
        isConnected && configuredPeer == TunnelConfig.targetIP && LocalDevVPN.isConnected
    }

    var statusTitle: String {
        if isSaving { return L10n.tr("Configuring VPN…") }
        switch status {
        case .connected: return L10n.tr("Connected")
        case .connecting, .reasserting: return L10n.tr("Connecting…")
        case .disconnecting: return L10n.tr("Disconnecting…")
        default: return L10n.tr("Disconnected")
        }
    }

    private func storedManager(for id: String) async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == id }
    }

    func refresh() async {
        guard !isSaving, let providerID else { return }
        revision += 1
        let current = revision
        do {
            let stored = try await storedManager(for: providerID)
            guard current == revision else { return }
            observe(stored)
        } catch {
            guard current == revision else { return }
            observe(nil)
            errorMessage = error.localizedDescription
        }
    }

    func connect() async {
        guard !isTransitioning, !isConnected, let providerID else { return }
        revision += 1
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let peer = TunnelConfig.targetIP
            guard TunnelConfig.isValidIP(peer) else { throw LocationEngineError.invalidIP }
            let stored = try await storedManager(for: providerID)
            let vpn = stored ?? NETunnelProviderManager()
            observe(vpn)
            // iOS Settings can start or stop a tunnel while this screen is open.
            guard [.disconnected, .invalid].contains(status) else { return }
            if stored == nil || configuredPeer != peer || !vpn.isEnabled {
                let settings = NETunnelProviderProtocol()
                settings.providerBundleIdentifier = providerID
                settings.serverAddress = peer
                settings.providerConfiguration = ["targetIP": peer]
                vpn.localizedDescription = L10n.tr("location developer tunnel")
                vpn.protocolConfiguration = settings
                vpn.isEnabled = true
                // The system presents its VPN consent sheet on the first save.
                try await vpn.saveToPreferences()
                try await vpn.loadFromPreferences()
            }
            observe(vpn)
            guard [.disconnected, .invalid].contains(status) else { return }
            try vpn.connection.startVPNTunnel()
            expectsConnection = true
            // startVPNTunnel can return before the session posts .connecting.
            // The real status notification supplies the final result.
            status = .connecting
        } catch {
            expectsConnection = false
            status = manager?.connection.status ?? .invalid
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        guard !isSaving, let manager, canDisconnect else { return }
        revision += 1
        expectsConnection = false
        errorMessage = nil
        manager.connection.stopVPNTunnel()
        status = .disconnecting
    }

    private func observe(_ vpn: NETunnelProviderManager?) {
        manager = vpn
        statusObserver = nil
        guard let connection = vpn?.connection else {
            updateStatus(.invalid)
            return
        }
        updateStatus(connection.status)
        statusObserver = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange, object: connection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak connection] _ in
                guard let connection else { return }
                self?.updateStatus(connection.status)
            }
    }

    private func updateStatus(_ newStatus: NEVPNStatus) {
        if expectsConnection && (newStatus == .disconnected || newStatus == .invalid) {
            errorMessage = L10n.tr("The built-in VPN could not connect. Check VPN permissions or use an external tunnel.")
            expectsConnection = false
        } else if newStatus == .connected {
            expectsConnection = false
            errorMessage = nil
        }
        status = newStatus
    }
}
