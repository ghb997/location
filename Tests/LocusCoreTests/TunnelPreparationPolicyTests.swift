import XCTest
@testable import LocusCore

final class TunnelPreparationPolicyTests: XCTestCase {
    @MainActor
    func testManualPortSkipsDiscovery() async throws {
        let fake = NetworkFake()
        let endpoint = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: false, manualPort: 50000, transport: fake)
        XCTAssertEqual(endpoint.port, 50000)
        XCTAssertEqual(fake.calls, ["probe:50000"])
    }

    @MainActor
    func testStaleDiscoveredPortFallsBackExactlyOnce() async throws {
        let fake = NetworkFake()
        fake.discovered = TunnelEndpoint(ip: "10.7.0.1", port: 50000, source: .bonjour)
        fake.probeErrors = [TunnelNetworkError.probeTimeout, nil]
        let endpoint = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: true, manualPort: 60000, transport: fake)
        XCTAssertEqual(endpoint.source, .fallback)
        XCTAssertEqual(fake.calls, ["discover", "probe:50000", "probe:49152"])
    }

    @MainActor
    func testNoDiscoveryResultUsesOldPort() async throws {
        let fake = NetworkFake()
        _ = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: true, manualPort: 50000, transport: fake)
        XCTAssertEqual(fake.calls, ["discover", "probe:49152"])
    }

    @MainActor
    func testCancelledProbeDoesNotStartFallbackConnection() async {
        let fake = NetworkFake()
        fake.discovered = TunnelEndpoint(ip: "10.7.0.1", port: 50000, source: .bonjour)
        fake.probeErrors = [CancellationError()]
        do {
            _ = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: true, manualPort: 49152, transport: fake)
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fake.calls, ["discover", "probe:50000"])
    }

    @MainActor
    func testDeniedPermissionDoesNotTriggerFallback() async {
        let fake = NetworkFake()
        fake.discovered = TunnelEndpoint(ip: "10.7.0.1", port: 50000, source: .bonjour)
        fake.probeErrors = [TunnelNetworkError.localNetworkDenied]
        do {
            _ = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: true, manualPort: 49152, transport: fake)
            XCTFail("Permission failure must propagate")
        } catch TunnelNetworkError.localNetworkDenied { }
        catch { XCTFail("Unexpected failure: \(error)") }
        XCTAssertEqual(fake.calls, ["discover", "probe:50000"])
    }

    @MainActor
    func testDiscoveryCancellationDoesNotProbe() async {
        let fake = NetworkFake()
        fake.discoveryError = CancellationError()
        do {
            _ = try await TunnelPreparationPolicy.prepare(targetIP: "10.7.0.1", automatic: true, manualPort: 49152, transport: fake)
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fake.calls, ["discover"])
    }
}

@MainActor
private final class NetworkFake: TunnelNetworkPreparing {
    var discovered: TunnelEndpoint?
    var discoveryError: Error?
    var probeErrors: [Error?] = []
    var calls: [String] = []
    func discover(targetIP: String) async throws -> TunnelEndpoint? {
        calls.append("discover")
        if let discoveryError { throw discoveryError }
        return discovered
    }
    func probe(_ endpoint: TunnelEndpoint) async throws {
        calls.append("probe:\(endpoint.port)")
        if !probeErrors.isEmpty, let error = probeErrors.removeFirst() { throw error }
    }
}
