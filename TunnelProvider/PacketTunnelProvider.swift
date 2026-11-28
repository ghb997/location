// Adapted from LocalDevVPN's PacketTunnelProvider by Stossy11 and contributors.
// Copyright (c) 2025 SideStore Team. See Vendor/LocalDevVPN/LocalDevVPN-LICENSE.txt.
import Darwin
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let queue = DispatchQueue(label: "locus.tunnel.packets")
    private var activeSession: UUID?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let configuration = protocolConfiguration as? NETunnelProviderProtocol,
              let peer = configuration.providerConfiguration?["targetIP"] as? String,
              let settings = Self.settings(for: peer) else {
            completionHandler(POSIXError(.EINVAL))
            return
        }

        queue.async {
            let session = UUID()
            self.activeSession = session
            self.setTunnelNetworkSettings(settings) { error in
                self.queue.async {
                    guard self.activeSession == session else {
                        completionHandler(POSIXError(.ECANCELED))
                        return
                    }
                    if let error {
                        self.activeSession = nil
                        completionHandler(error)
                        return
                    }
                    self.readPackets(for: session)
                    completionHandler(nil)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.activeSession = nil
            completionHandler()
        }
    }

    static func settings(for peer: String) -> NEPacketTunnelNetworkSettings? {
        var address = in_addr()
        guard inet_pton(AF_INET, peer, &address) == 1 else { return nil }
        // Default LocalDevVPN /32 interface. Its address must differ from the peer.
        let interfaceAddress = peer == "10.7.1.1" ? "10.7.1.2" : "10.7.1.1"
        let hostMask = "255.255.255.255"
        let ipv4 = NEIPv4Settings(addresses: [interfaceAddress], subnetMasks: [hostMask])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: peer, subnetMask: hostMask)]
        ipv4.excludedRoutes = [.default()]
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: peer)
        settings.ipv4Settings = ipv4
        return settings
    }

    private func readPackets(for session: UUID) {
        packetFlow.readPacketObjects { [weak self] packets in
            guard let self else { return }
            self.queue.async {
                guard self.activeSession == session else { return }
                let reflected = packets.compactMap(Self.reflectIPv4)
                if !reflected.isEmpty && !self.packetFlow.writePacketObjects(reflected) {
                    self.activeSession = nil
                    self.cancelTunnelWithError(POSIXError(.EIO))
                    return
                }
                self.readPackets(for: session)
            }
        }
    }

    static func reflectIPv4(_ packet: NEPacket) -> NEPacket? {
        var data = packet.data
        guard packet.protocolFamily == sa_family_t(AF_INET), let firstByte = data.first,
              firstByte >> 4 == 4 else { return nil }
        let headerBytes = Int(firstByte & 0x0f) * 4
        guard headerBytes >= 20, data.count >= headerBytes else { return nil }

        // Swapping the two address fields preserves IPv4 and transport checksums.
        // Byte access also works for buffers with no UInt32 alignment guarantee.
        let start = data.startIndex
        for offset in 0..<4 {
            data.swapAt(start + 12 + offset, start + 16 + offset)
        }
        return NEPacket(data: data, protocolFamily: packet.protocolFamily)
    }
}
