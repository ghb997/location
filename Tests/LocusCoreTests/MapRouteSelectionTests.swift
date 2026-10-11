import XCTest
@testable import LocusCore

final class MapRouteSelectionTests: XCTestCase {
    private func track(_ name: String, longitude: Double = 0) -> RouteTrack {
        RouteTrack(name: name, segments: [RouteSegment(points: [
            RoutePoint(latitude: 0, longitude: longitude),
            RoutePoint(latitude: 0, longitude: longitude + 0.001)
        ])])
    }

    func testImportedDraftIsVisibleWithoutChangingPausedRouteProgress() throws {
        var active = RoutePlaybackCore(track: track("Active"), speed: 2, variation: { 1 })
        active.start(at: 0)
        let point = try XCTUnwrap(active.proposedSample(at: 0.5))
        active.confirm(point, at: 0.6)
        active.pause(.user)
        let savedProgress = active.snapshot
        let draft = track("Imported", longitude: 10)
        var selection = MapRouteSelection()
        let importRevision = selection.beginTargetChange()

        XCTAssertTrue(selection.previewDraft(replacingTarget: importRevision))
        XCTAssertEqual(selection.displayedTrack(draft: draft, current: active.track)?.id, draft.id)
        XCTAssertEqual(active.snapshot, savedProgress)
        XCTAssertEqual(active.confirmed, point)

        selection.show(.current)
        XCTAssertEqual(selection.displayedTrack(draft: draft, current: active.track)?.id, active.track.id)
        XCTAssertEqual(active.snapshot.status, .paused)
    }

    func testCompletedActiveRouteCannotMaskNewDraft() throws {
        var active = RoutePlaybackCore(track: track("Completed"), speed: 2, variation: { 1 })
        active.start(at: 0)
        let finish = try XCTUnwrap(active.plan?.sample(at: 1000))
        active.confirm(finish, at: 0.5)
        XCTAssertEqual(active.snapshot.status, .completed)
        let draft = track("New route")
        var selection = MapRouteSelection()
        selection.previewDraft()
        XCTAssertEqual(selection.displayedTrack(draft: draft, current: active.track)?.id, draft.id)
        XCTAssertEqual(selection.resolvedSource(draft: draft, current: active.track), .draft)
    }

    func testCurrentDisplayFollowsRollbackAndDraftRemainsAvailable() {
        let original = track("Original")
        let candidate = track("Candidate")
        var selection = MapRouteSelection()
        selection.previewDraft()
        selection.show(.current)
        XCTAssertEqual(selection.displayedTrack(draft: candidate, current: candidate)?.id, candidate.id)
        // The session restores its paused snapshot after a failed route switch.
        XCTAssertEqual(selection.displayedTrack(draft: candidate, current: original)?.id, original.id)
        selection.show(.draft)
        XCTAssertEqual(selection.displayedTrack(draft: candidate, current: original)?.id, candidate.id)
    }

    func testMissingPreferredRouteFallsBackToAvailableRouteWithCorrectLabel() {
        let draft = track("Draft")
        let current = track("Current")
        var selection = MapRouteSelection()
        XCTAssertEqual(selection.displayedTrack(draft: draft, current: nil)?.id, draft.id)
        XCTAssertEqual(selection.resolvedSource(draft: draft, current: nil), .draft)
        selection.show(.draft)
        XCTAssertEqual(selection.displayedTrack(draft: nil, current: current)?.id, current.id)
        XCTAssertEqual(selection.resolvedSource(draft: nil, current: current), .current)
        XCTAssertNil(selection.displayedTrack(draft: nil, current: nil))
        XCTAssertNil(selection.resolvedSource(draft: nil, current: nil))
    }

    @MainActor
    func testLateSearchCannotReplaceSelectedDraftTarget() async {
        let state = PendingMapResult()
        let latch = MapSearchLatch()
        let revision = state.selection.beginTargetChange()
        let search = Task {
            await latch.wait()
            state.receiveSearch("stale search", revision: revision)
        }
        await latch.waitUntilStarted()
        state.selection.previewDraft()
        state.target = "selected draft start"
        await latch.release()
        await search.value
        XCTAssertEqual(state.target, "selected draft start")
    }

    @MainActor
    func testLateSearchCannotReplaceImportedDraftTarget() async {
        let state = PendingMapResult()
        let latch = MapSearchLatch()
        let searchRevision = state.selection.beginTargetChange()
        let search = Task {
            await latch.wait()
            state.receiveSearch("stale search", revision: searchRevision)
        }
        await latch.waitUntilStarted()
        let importRevision = state.selection.beginTargetChange()
        XCTAssertFalse(state.selection.acceptsTargetChange(searchRevision))
        XCTAssertTrue(state.selection.previewDraft(replacingTarget: importRevision))
        state.target = "imported draft start"
        await latch.release()
        await search.value
        XCTAssertEqual(state.target, "imported draft start")
    }

    func testSearchStartedAfterImportKeepsItsTargetWhenImportFinishes() {
        var selection = MapRouteSelection()
        let importRevision = selection.beginTargetChange()
        let newerSearch = selection.beginTargetChange()
        XCTAssertFalse(selection.previewDraft(replacingTarget: importRevision))
        XCTAssertTrue(selection.acceptsTargetChange(newerSearch))
        XCTAssertEqual(selection.source, .draft)
    }

    func testTargetRemovalAndNewSearchInvalidateOldResults() {
        var selection = MapRouteSelection()
        let firstSearch = selection.beginTargetChange()
        let secondSearch = selection.beginTargetChange()
        XCTAssertFalse(selection.acceptsTargetChange(firstSearch))
        XCTAssertTrue(selection.acceptsTargetChange(secondSearch))
        selection.beginTargetChange() // User removes the pin.
        XCTAssertFalse(selection.acceptsTargetChange(secondSearch))
    }

    func testFailedImportLeavesExistingPreviewSelected() {
        var selection = MapRouteSelection()
        let existing = track("Existing draft")
        let current = track("Current")
        selection.previewDraft()
        selection.beginTargetChange() // Failed preparation never installs a draft.
        XCTAssertEqual(selection.displayedTrack(draft: existing, current: current)?.id, existing.id)
        XCTAssertEqual(selection.source, .draft)
    }
}

@MainActor
private final class PendingMapResult {
    var selection = MapRouteSelection()
    var target: String?

    func receiveSearch(_ result: String, revision: UInt64) {
        guard selection.acceptsTargetChange(revision) else { return }
        target = result
    }
}

private actor MapSearchLatch {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finish: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { finish = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        finish?.resume()
        finish = nil
    }
}
