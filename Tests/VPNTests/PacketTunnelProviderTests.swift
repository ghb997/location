import Darwin
import NetworkExtension
import XCTest
@testable import LocalTunnel

final class PacketTunnelProviderTests: XCTestCase {
    func testRoutesOnlyTheConfiguredPeer() throws {
        for peer in ["10.7.0.1", "172.20.4.17", "10.7.1.1"] {
            let settings = try XCTUnwrap(PacketTunnelProvider.settings(for: peer))
            let ipv4 = try XCTUnwrap(settings.ipv4Settings)
            XCTAssertEqual(ipv4.addresses, [peer == "10.7.1.1" ? "10.7.1.2" : "10.7.1.1"])
            XCTAssertEqual(ipv4.subnetMasks, ["255.255.255.255"])
            XCTAssertEqual(ipv4.includedRoutes?.map(\.destinationAddress), [peer])
            XCTAssertEqual(ipv4.includedRoutes?.map(\.destinationSubnetMask), ["255.255.255.255"])
            XCTAssertEqual(ipv4.excludedRoutes?.map(\.destinationSubnetMask), ["0.0.0.0"])
            XCTAssertNil(settings.ipv6Settings)
            XCTAssertNil(settings.dnsSettings)
        }
        XCTAssertNil(PacketTunnelProvider.settings(for: "not-an-address"))
    }

    func testReflectionChangesOnlyTheIPv4Addresses() throws {
        let header: [UInt8] = [0x45, 0, 0, 28, 0, 1, 0x40, 0, 64, 17, 0x25, 0xc1]
        let source: [UInt8] = [10, 7, 1, 1]
        let destination: [UInt8] = [10, 7, 0, 1]
        let udp: [UInt8] = [0xc0, 6, 0xc0, 0, 0, 8, 0, 0]
        let packet = NEPacket(data: Data(header + source + destination + udp), protocolFamily: sa_family_t(AF_INET))
        let reflected = try XCTUnwrap(PacketTunnelProvider.reflectIPv4(packet))
        XCTAssertEqual(reflected.protocolFamily, packet.protocolFamily)
        XCTAssertEqual(reflected.data, Data(header + destination + source + udp))
        XCTAssertEqual(PacketTunnelProvider.reflectIPv4(reflected)?.data, packet.data)
    }

    func testDropsUnsupportedAndTruncatedPackets() {
        func reflect(_ bytes: [UInt8], _ family: Int32 = AF_INET) -> NEPacket? {
            PacketTunnelProvider.reflectIPv4(NEPacket(data: Data(bytes), protocolFamily: sa_family_t(family)))
        }
        let ipv4 = [UInt8(0x45)] + [UInt8](repeating: 0, count: 19)
        XCTAssertNil(reflect(ipv4, AF_INET6))
        XCTAssertNil(reflect([]))
        XCTAssertNil(reflect(Array(ipv4.prefix(19))))
        for firstByte in [UInt8(0x40), 0x46, 0x65] {
            var malformed = ipv4
            malformed[0] = firstByte
            XCTAssertNil(reflect(malformed))
        }
    }
}
