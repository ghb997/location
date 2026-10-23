import XCTest
@testable import LocusCore

@MainActor
final class FreshEndpointRestorationTests: XCTestCase {
    func testFailedOldClearDiscoversNewPortBeforeReconnectAndNeverWrites() async {
        let transport = RestoreTransport(initial: .reconnect("pairing"))
        let result = await FreshEndpointRestorationPolicy.restore(transport)
        guard case .success = result else { return XCTFail("Fresh endpoint should restore") }
        XCTAssertEqual(transport.calls, ["old-clear-and-disconnect", "discover-and-probe", "connect:54321", "clear-and-disconnect"])
    }

    func testHealthyClearDoesNotDependOnDiscoveryOrReconnect() async {
        let transport = RestoreTransport(initial: .restored)
        transport.discoveryFails = true
        let result = await FreshEndpointRestorationPolicy.restore(transport)
        guard case .success = result else { return XCTFail("Existing clear is sufficient") }
        XCTAssertEqual(transport.calls, ["old-clear-and-disconnect"])
    }

    func testDiscoveryFailureNeverReusesCachedEndpoint() async {
        let transport = RestoreTransport(initial: .reconnect("pairing"))
        transport.discoveryFails = true
        let result = await FreshEndpointRestorationPolicy.restore(transport)
        guard case .failure = result else { return XCTFail("Restoration must stay unconfirmed") }
        XCTAssertEqual(transport.calls, ["old-clear-and-disconnect", "discover-and-probe"])
    }

    func testConnectFailureDoesNotClearAnInvalidHandle() async {
        let transport = RestoreTransport(initial: .reconnect("pairing"))
        transport.connectionFails = true
        let result = await FreshEndpointRestorationPolicy.restore(transport)
        guard case .failure = result else { return XCTFail("Restoration must stay unconfirmed") }
        XCTAssertEqual(transport.calls, ["old-clear-and-disconnect", "discover-and-probe", "connect:54321"])
    }

    func testFailedReconnectClearIsNotRetriedIndefinitely() async {
        let transport = RestoreTransport(initial: .reconnect("pairing"))
        transport.finalClearFails = true
        let result = await FreshEndpointRestorationPolicy.restore(transport)
        guard case .failure = result else { return XCTFail("Restoration must stay unconfirmed") }
        XCTAssertEqual(transport.calls.filter { $0 == "clear-and-disconnect" }.count, 1)
    }

    func testStopReservationRemainsClosedDuringDiscoveryAndLateNativeReturn() async {
        let gate = NativeOperationGate()
        let id = UUID()
        XCTAssertTrue(gate.reserveStop())
        gate.submit(id: id, kind: .clear)
        let transport = RestoreTransport(initial: .reconnect("pairing"))
        transport.onDiscovery = {
            gate.timeOut(id: id)
            XCTAssertTrue(gate.isDraining)
            XCTAssertFalse(gate.canWrite)
            XCTAssertFalse(gate.reserveStop())
        }
        transport.onClear = {
            XCTAssertFalse(gate.canWrite)
            XCTAssertTrue(gate.stopReserved)
        }
        _ = await FreshEndpointRestorationPolicy.restore(transport)
        XCTAssertFalse(gate.canWrite)
        gate.complete(id: id)
        XCTAssertTrue(gate.canWrite)
    }
}

private enum RestorationTestError: Error { case unavailable }

@MainActor
private final class RestoreTransport: FreshEndpointRestorationTransport {
    let initial: ExistingRestorationResult<String, RestorationTestError>
    var calls: [String] = []
    var discoveryFails = false
    var connectionFails = false
    var finalClearFails = false
    var onDiscovery: (() -> Void)?
    var onClear: (() -> Void)?
    init(initial: ExistingRestorationResult<String, RestorationTestError>) { self.initial = initial }

    func clearExisting() async -> ExistingRestorationResult<String, RestorationTestError> {
        calls.append("old-clear-and-disconnect")
        return initial
    }
    func resolveEndpoint(for target: String) async -> Result<TunnelEndpoint, RestorationTestError> {
        calls.append("discover-and-probe")
        onDiscovery?()
        await Task.yield()
        return discoveryFails ? .failure(.unavailable) : .success(TunnelEndpoint(ip: "10.7.0.1", port: 54321, source: .bonjour))
    }
    func connect(target: String, endpoint: TunnelEndpoint) async -> Result<Void, RestorationTestError> {
        calls.append("connect:\(endpoint.port)")
        return connectionFails ? .failure(.unavailable) : .success(())
    }
    func clearAndDisconnect() async -> Result<Void, RestorationTestError> {
        calls.append("clear-and-disconnect")
        onClear?()
        return finalClearFails ? .failure(.unavailable) : .success(())
    }
}
