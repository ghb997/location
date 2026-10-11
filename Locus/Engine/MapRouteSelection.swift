import Foundation

/// Map presentation never replaces the session's active route. A newly selected
/// draft can be inspected while the session keeps its paused route and progress.
struct MapRouteSelection: Sendable {
    enum Source: String, CaseIterable, Sendable {
        case draft
        case current
    }

    private(set) var source: Source = .current
    private var targetRevision: UInt64 = 0

    /// Every user intent that can move the target or camera owns a revision.
    /// Cancellation alone cannot reject a search whose provider returns late.
    @discardableResult
    mutating func beginTargetChange() -> UInt64 {
        targetRevision &+= 1
        return targetRevision
    }

    func acceptsTargetChange(_ revision: UInt64) -> Bool {
        revision == targetRevision
    }

    /// Installing a draft always makes it visible, but a late import/build must
    /// not replace a target selected after that preparation started.
    @discardableResult
    mutating func previewDraft(replacingTarget revision: UInt64? = nil) -> Bool {
        source = .draft
        if let revision, !acceptsTargetChange(revision) { return false }
        beginTargetChange()
        return true
    }

    mutating func show(_ source: Source) {
        self.source = source
    }

    func resolvedSource(draft: RouteTrack?, current: RouteTrack?) -> Source? {
        switch source {
        case .draft: return draft != nil ? .draft : (current != nil ? .current : nil)
        case .current: return current != nil ? .current : (draft != nil ? .draft : nil)
        }
    }

    func displayedTrack(draft: RouteTrack?, current: RouteTrack?) -> RouteTrack? {
        switch resolvedSource(draft: draft, current: current) {
        case .draft: return draft
        case .current: return current
        case nil: return nil
        }
    }
}
