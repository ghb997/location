import XCTest
@testable import LocusCore

final class DiagnosticHistoryTests: XCTestCase {
    func testSuccessfulHeartbeatsDoNotEraseLastFailureAndBuffersStayBounded() {
        var history = DiagnosticHistory(capacity: 3, failureCapacity: 2)
        history.append(operation: 1, elapsed: 1, stage: .clear, outcome: .failed, error: .locationClear)
        for operation in 2...100 {
            history.append(operation: operation, elapsed: 0.2, stage: .set, outcome: .succeeded)
        }
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.recentFailures.count, 1)
        XCTAssertTrue(history.exportText.contains("error=locationClear"))
        for operation in 101...105 {
            history.append(operation: operation, elapsed: 1, stage: .probe, outcome: .failed, network: .probeTimeout)
        }
        XCTAssertEqual(history.recentFailures.count, 2)
        XCTAssertEqual(history.recentFailures.map(\.operation), [104, 105])
    }

    func testExportHasCodesStagesCategoriesAndNoSensitiveNativeFields() {
        var history = DiagnosticHistory()
        let secret = "PIN 987654 latitude=31.2304 longitude=121.4737 /private/pairing.plist device=secret"
        history.append(operation: 1, elapsed: 2.5, stage: .clear, outcome: .failed,
                       endpoint: TunnelEndpoint(ip: "10.7.0.1", port: 54321, source: .bonjour),
                       error: .locationClear, network: .probeTimeout,
                       native: NativeTunnelError(stage: .clear, code: 2, subcode: 7, message: secret))
        let exported = history.exportText
        for value in ["native=2/7", "stage=clear", "port=54321", "network=probeTimeout"] { XCTAssertTrue(exported.contains(value)) }
        for value in ["987654", "31.2304", "121.4737", "/private", "10.7.0.1", "device=secret"] { XCTAssertFalse(exported.contains(value)) }
    }

    func testNetworkErrorsRemainDistinctAndElapsedIsFinite() {
        XCTAssertEqual(DiagnosticHistory.NetworkCategory(TunnelNetworkError.probeTimeout), .probeTimeout)
        XCTAssertEqual(DiagnosticHistory.NetworkCategory(TunnelNetworkError.localNetworkDenied), .localNetworkDenied)
        XCTAssertEqual(DiagnosticHistory.NetworkCategory(CancellationError()), .cancelled)
        var history = DiagnosticHistory()
        history.append(operation: 1, elapsed: .nan, stage: .probe, outcome: .failed)
        XCTAssertEqual(history.entries.first?.elapsed, 0)
    }
}
