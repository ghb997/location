import Darwin
import Foundation
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
