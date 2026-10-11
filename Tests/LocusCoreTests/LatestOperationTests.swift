import XCTest
@testable import LocusCore

final class LatestOperationTests: XCTestCase {
    @MainActor
    func testReplacedImportCannotPublishEvenWhenReaderIgnoresCancellation() async throws {
        let loader = LatestOperation<String>()
        let latch = ImportLatch()
        let old = Task {
            try await loader.perform {
                await latch.wait()
                return "old draft"
            }
        }
        await latch.waitUntilStarted()
        let latest = try await loader.perform { "new draft" }
        await latch.release()
        XCTAssertEqual(latest, "new draft")
        do { _ = try await old.value; XCTFail("Stale import published") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor
    func testCancellationRejectsLateImportAndNextImportStillWorks() async throws {
        let loader = LatestOperation<String>()
        let latch = ImportLatch()
        let old = Task { try await loader.perform { await latch.wait(); return "cancelled" } }
        await latch.waitUntilStarted()
        loader.cancel()
        await latch.release()
        do { _ = try await old.value; XCTFail("Cancelled import published") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let next = try await loader.perform { "next" }
        XCTAssertEqual(next, "next")
    }
}

private actor ImportLatch {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finish: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { finish = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { finish?.resume(); finish = nil }
}
