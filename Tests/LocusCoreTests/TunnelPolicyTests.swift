import XCTest
@testable import LocusCore

final class TunnelPolicyTests: XCTestCase {
    func testRoutedPeerUsesVPNSourceEvenWhenItIsInADifferentSubnet() {
        for name in ["utun3", "ipsec0", "ppp0"] {
            let interfaces = [(name: "en0", address: "192.168.1.8"), (name: name, address: "10.7.1.1")]
            XCTAssertTrue(TunnelPolicy.hasVPNInterface(targetIP: "10.7.0.1", routeSource: "10.7.1.1",
                                                       interfaces: interfaces), name)
        }
    }

    func testNonVPNRouteTakesPrecedenceOverUnrelatedVPNInPeerSubnet() {
        let interfaces = [(name: "en0", address: "10.7.0.5"), (name: "utun0", address: "10.7.0.8")]
        XCTAssertFalse(TunnelPolicy.hasVPNInterface(targetIP: "10.7.0.1", routeSource: "10.7.0.5",
                                                    interfaces: interfaces))
    }

    func testLegacyInterfaceHintUsesConfiguredPeerSubnetAndRequiresAVPN() {
        let peer = "172.20.4.1"
        XCTAssertTrue(TunnelPolicy.hasVPNInterface(targetIP: peer, routeSource: nil,
                                                   interfaces: [("utun2", "172.20.4.9")]))
        XCTAssertFalse(TunnelPolicy.hasVPNInterface(targetIP: peer, routeSource: nil,
                                                    interfaces: [("en0", peer), ("utun1", "172.20.40.9")]))
        XCTAssertFalse(TunnelPolicy.hasVPNInterface(targetIP: peer, routeSource: nil, interfaces: []))
    }

    func testTunnelSettingAcceptsCIDRWithoutChangingThePeerAddress() {
        XCTAssertEqual(TunnelConfig.normalizedTargetIP(" 10.7.0.1/32\n"), "10.7.0.1")
        XCTAssertEqual(TunnelConfig.normalizedTargetIP("172.20.4.17/24"), "172.20.4.17")
        XCTAssertEqual(TunnelConfig.normalizedTargetIP("172.20.4.17/0"), "172.20.4.17")
        XCTAssertEqual(TunnelConfig.normalizedTargetIP("172.20.4.17"), "172.20.4.17")
        XCTAssertEqual(TunnelConfig.normalizedTargetIP("  "), TunnelConfig.defaultIP)
        for value in ["/32", "10.7.0.1/", "10.7.0.1/33", "10.7.0.1/-1", "10.7.0.1/24/32", "10.7.0.256/32"] {
            XCTAssertNil(TunnelConfig.normalizedTargetIP(value), value)
        }
        XCTAssertFalse(TunnelConfig.isValidIP("10.7.0.1/32"))
    }

    func testTunnelSettingReadsStoredCIDRAndKeepsLastEndpointAfterInvalidInput() {
        let defaults = UserDefaults.standard
        let key = TunnelConfig.defaultsKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        defaults.set("172.20.4.17/24", forKey: key)
        XCTAssertEqual(TunnelConfig.targetIP, "172.20.4.17")
        XCTAssertTrue(TunnelConfig.setTargetIP("10.7.0.1/32"))
        XCTAssertEqual(defaults.string(forKey: key), "10.7.0.1")
        XCTAssertFalse(TunnelConfig.setTargetIP("10.7.1.1/bad"))
        XCTAssertEqual(TunnelConfig.targetIP, "10.7.0.1")
    }

    func testDiscoveryRejectsOtherDevicesButAcceptsDeviceAndTunnelAddresses() {
        XCTAssertFalse(TunnelPolicy.accepts(addresses: ["192.168.1.7"], targetIP: "10.7.0.1", localAddresses: ["192.168.1.8"]))
        XCTAssertTrue(TunnelPolicy.accepts(addresses: ["192.168.1.8"], targetIP: "10.7.0.1", localAddresses: ["192.168.1.8"]))
        XCTAssertTrue(TunnelPolicy.accepts(addresses: ["10.7.0.1"], targetIP: "10.7.0.1", localAddresses: []))
        XCTAssertFalse(TunnelPolicy.accepts(addresses: [], targetIP: "10.7.0.1", localAddresses: []))
    }

    func testDiagnosticExportNeverIncludesNativeSecrets() {
        let detail = NativeTunnelError(stage: .pairing, code: 2, subcode: 7,
            message: "PIN 123456 /private/pairing.plist 10.7.0.1 identifier=secret")
        let output = TunnelPolicy.exportSummary(stage: .pairing, source: .bonjour, port: 54321, error: detail, draining: true)
        XCTAssertTrue(output.contains("2 / 7"))
        XCTAssertTrue(output.contains("54321"))
        for secret in ["123456", "/private", "10.7.0.1", "identifier=secret"] { XCTAssertFalse(output.contains(secret)) }
    }

    @MainActor
    func testStopReservesQueueAndLateWriteCannotReopenIt() async {
        let gate = NativeOperationGate()
        let write = UUID(), stop = UUID()
        XCTAssertTrue(gate.canWrite)
        gate.submit(id: write, kind: .write)
        XCTAssertFalse(gate.canWrite)
        XCTAssertTrue(gate.reserveStop())
        XCTAssertFalse(gate.reserveStop())
        gate.submit(id: stop, kind: .clear)
        XCTAssertEqual(gate.pending.map(\.id), [write, stop])
        gate.complete(id: write)
        XCTAssertFalse(gate.canWrite)
        XCTAssertTrue(gate.stopReserved)
        gate.complete(id: stop)
        XCTAssertTrue(gate.canWrite)
    }

    @MainActor
    func testWatchdogKeepsNativeWorkerOccupiedUntilRealCallback() async {
        let gate = NativeOperationGate()
        let write = UUID(), stop = UUID()
        gate.submit(id: write, kind: .write)
        gate.timeOut(id: write)
        XCTAssertTrue(gate.isDraining)
        XCTAssertFalse(gate.canWrite)
        XCTAssertTrue(gate.reserveStop())
        gate.submit(id: stop, kind: .clear)
        gate.timeOut(id: stop)
        gate.complete(id: write)
        XCTAssertTrue(gate.isDraining)
        XCTAssertFalse(gate.canWrite)
        gate.complete(id: stop)
        XCTAssertFalse(gate.isDraining)
        XCTAssertTrue(gate.canWrite)
    }

    func testWatchdogAndLateNativeResultResumeContinuationOnlyOnce() async {
        let value: String = await withCheckedContinuation { continuation in
            let completion = OperationCompletion(continuation)
            XCTAssertTrue(completion.finish("timed out"))
            XCTAssertFalse(completion.finish("late success"))
        }
        XCTAssertEqual(value, "timed out")
    }

    func testDeadlineAndCancellationBlockTheNextNativeStage() {
        var now: TimeInterval = 100
        let control = NativeRequestControl(seconds: 30, clock: { now })
        XCTAssertFalse(control.hasExpired)
        now = 131
        XCTAssertTrue(control.hasExpired)
        XCTAssertEqual(control.remainingSeconds, 0)
        let cancelled = NativeRequestControl(seconds: 30)
        cancelled.cancel()
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.hasExpired)
    }

    func testBrokenClearReconnectsWithoutWritingCoordinates() {
        var transport = RestoreFake(connected: true, results: [.failure(.broken), .success(())])
        let result = LocationRestorationPolicy.restore(&transport)
        guard case .success = result else { return XCTFail("Recovery should succeed") }
        XCTAssertEqual(transport.calls, ["clear", "disconnect", "connect", "clear", "disconnect"])
    }

    @MainActor
    func testQueuedRestorationStillClearsOnceAfterItsUIWatchdog() async {
        var now: TimeInterval = 0
        let control = NativeRequestControl(seconds: 30, purpose: .restoration, clock: { now })
        let gate = NativeOperationGate()
        let write = UUID(), stop = UUID()
        gate.submit(id: write, kind: .write)
        XCTAssertTrue(gate.reserveStop())
        gate.submit(id: stop, kind: .clear)
        now = 31
        gate.timeOut(id: stop)
        XCTAssertTrue(control.hasExpired)
        XCTAssertTrue(control.mayStartNextStage)
        XCTAssertTrue(gate.isDraining)
        gate.complete(id: write)
        var transport = RestoreFake(connected: true, results: [.success(())], control: control)
        let result = LocationRestorationPolicy.restore(&transport)
        guard case .success = result else { return XCTFail("Submitted restoration must survive queue delay") }
        XCTAssertEqual(transport.calls, ["clear", "disconnect"])
        XCTAssertFalse(gate.canWrite)
        gate.complete(id: stop)
        XCTAssertTrue(gate.canWrite)
    }

    func testRestartRecoveryConnectsThenClears() {
        var transport = RestoreFake(connected: false, results: [.success(())])
        _ = LocationRestorationPolicy.restore(&transport)
        XCTAssertEqual(transport.calls, ["connect", "clear", "disconnect"])
    }

    func testRestorationReconnectStagesSurviveTheUIWatchdog() {
        var now: TimeInterval = 0
        let control = NativeRequestControl(seconds: 30, purpose: .restoration, clock: { now })
        now = 60
        var transport = RestoreFake(connected: false, results: [.success(())], control: control)
        let result = LocationRestorationPolicy.restore(&transport)
        guard case .success = result else { return XCTFail("Recovery must continue after a queue delay") }
        XCTAssertEqual(transport.calls, ["connect", "clear", "disconnect"])
    }

    func testFailedRestorationReturnsFailureAndDoesNotRetryForever() {
        var transport = RestoreFake(connected: true, results: [.failure(.broken), .failure(.broken)])
        let result = LocationRestorationPolicy.restore(&transport)
        guard case .failure = result else { return XCTFail("Restoration must remain unconfirmed") }
        XCTAssertEqual(transport.calls.filter { $0 == "clear" }.count, 2)
        XCTAssertEqual(transport.calls.last, "disconnect")
    }

    func testFailedReconnectNeverCallsClearOnAnInvalidHandle() {
        var transport = RestoreFake(connected: false, results: [], connectionFailure: true)
        let result = LocationRestorationPolicy.restore(&transport)
        guard case .failure = result else { return XCTFail("Connection failure must propagate") }
        XCTAssertEqual(transport.calls, ["connect", "disconnect"])
    }

    func testSuccessfulClearDoesNotReconnect() {
        var transport = RestoreFake(connected: true, results: [.success(())])
        _ = LocationRestorationPolicy.restore(&transport)
        XCTAssertEqual(transport.calls, ["clear", "disconnect"])
    }
}

private enum RestoreError: Error { case broken }
private struct RestoreFake: LocationRestorationTransport {
    var connected: Bool
    var results: [Result<Void, RestoreError>]
    var connectionFailure = false
    var control: NativeRequestControl? = nil
    var calls: [String] = []
    var hasConnection: Bool { connected }
    var canReconnect: Bool { true }
    mutating func connect() -> Result<Void, RestoreError> {
        if let control, !control.mayStartNextStage { return .failure(.broken) }
        calls.append("connect")
        connected = !connectionFailure
        return connectionFailure ? .failure(.broken) : .success(())
    }
    mutating func clear() -> Result<Void, RestoreError> {
        if let control, !control.mayStartNextStage { return .failure(.broken) }
        calls.append("clear")
        return results.removeFirst()
    }
    mutating func disconnect() { calls.append("disconnect"); connected = false }
}
