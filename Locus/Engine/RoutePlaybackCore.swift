import Foundation

enum RoutePlaybackStatus: String, Equatable, Sendable {
    case idle, playing, pausing, paused, awaitingNextSegment, completed
}

enum RoutePauseReason: String, Equatable, Sendable {
    case user, transportInterrupted, executionInterrupted

    var title: String {
        switch self {
        case .user: return L10n.tr("Route paused")
        case .transportInterrupted: return L10n.tr("Connection interrupted. Reconnect, then continue the route.")
        case .executionInterrupted: return L10n.tr("Route paused after an execution delay. Continue when ready.")
        }
    }
}

struct RoutePlaybackSnapshot: Equatable, Sendable {
    var status: RoutePlaybackStatus = .idle
    var pauseReason: RoutePauseReason?
    var segmentIndex: Int = 0
    var progress: Double = 0
    var completedDistance: Double = 0
    var totalDistance: Double = 0
}

struct RouteTimingSample: Equatable, Sendable {
    var point: RoutePoint
    var elapsed: Double
    var distance: Double
    var finished: Bool
}

/// Immutable timeline: each original edge has one speed, including after resume.
struct RouteTimingPlan: Sendable {
    let points: [RoutePoint]
    let cumulativeTime: [Double]
    let cumulativeDistance: [Double]
    var duration: Double { cumulativeTime.last ?? 0 }
    var distance: Double { cumulativeDistance.last ?? 0 }

    init(segment: RouteSegment, speed: Double, variation: () -> Double = { Double.random(in: 0.88...1.12) }) {
        points = segment.points
        var times = [0.0]
        var distances = [0.0]
        for (a, b) in zip(segment.points, segment.points.dropFirst()) {
            let length = RouteGeometry.distance(from: a.coordinate, to: b.coordinate)
            let rawVariation = variation()
            let factor = rawVariation.isFinite ? min(1.12, max(0.88, rawVariation)) : 1
            let edgeSpeed = speed.isFinite && speed > 0 ? max(0.8, speed * factor) : 0.8
            distances.append((distances.last ?? 0) + length)
            times.append((times.last ?? 0) + length / edgeSpeed)
        }
        cumulativeTime = times
        cumulativeDistance = distances
    }

    func sample(at elapsed: Double) -> RouteTimingSample? {
        guard let first = points.first, let last = points.last else { return nil }
        let time = elapsed.isFinite ? min(duration, max(0, elapsed)) : 0
        guard points.count > 1, duration > 0, time < duration else {
            return RouteTimingSample(point: last, elapsed: duration, distance: distance, finished: true)
        }
        if time == 0 { return RouteTimingSample(point: first, elapsed: 0, distance: 0, finished: false) }
        var lower = 0
        var upper = cumulativeTime.count - 1
        while lower + 1 < upper {
            let mid = (lower + upper) / 2
            if cumulativeTime[mid] <= time { lower = mid } else { upper = mid }
        }
        let span = cumulativeTime[upper] - cumulativeTime[lower]
        let fraction = span > 0 ? (time - cumulativeTime[lower]) / span : 1
        let point = RoutePoint(RouteGeometry.interpolate(from: points[lower].coordinate, to: points[upper].coordinate, fraction: fraction))
        let traveled = cumulativeDistance[lower] + (cumulativeDistance[upper] - cumulativeDistance[lower]) * fraction
        return RouteTimingSample(point: point, elapsed: time, distance: traveled, finished: false)
    }
}

/// The session owns asynchronous writes; this value commits only confirmed samples.
struct RoutePlaybackCore: Sendable {
    static let interval = 0.5
    static let stallLimit = 2.0

    let track: RouteTrack
    let plans: [RouteTimingPlan]
    private(set) var snapshot: RoutePlaybackSnapshot
    private(set) var confirmed: RouteTimingSample?
    private var anchor = 0.0
    private var baseElapsed = 0.0
    private var lastActivity = 0.0

    init(track: RouteTrack, speed: Double, variation: () -> Double = { Double.random(in: 0.88...1.12) }) {
        self.track = track
        plans = track.segments.map { RouteTimingPlan(segment: $0, speed: speed, variation: variation) }
        let index = track.segments.firstIndex(where: \.canPlay) ?? 0
        snapshot = RoutePlaybackSnapshot(segmentIndex: index, totalDistance: plans.reduce(0) { $0 + $1.distance })
    }

    var plan: RouteTimingPlan? { plans.indices.contains(snapshot.segmentIndex) ? plans[snapshot.segmentIndex] : nil }
    var nextSegmentIndex: Int? {
        track.segments.indices.first { $0 > snapshot.segmentIndex && track.segments[$0].canPlay }
    }

    mutating func start(at now: Double) {
        snapshot.status = .playing
        snapshot.pauseReason = nil
        anchor = now
        lastActivity = now
        baseElapsed = confirmed?.elapsed ?? 0
    }

    mutating func requestPause() {
        guard snapshot.status == .playing || snapshot.status == .idle else { return }
        snapshot.status = .pausing
    }

    mutating func pause(_ reason: RoutePauseReason) {
        snapshot.status = .paused
        snapshot.pauseReason = reason
        baseElapsed = confirmed?.elapsed ?? 0
    }

    mutating func proposedSample(at now: Double) -> RouteTimingSample? {
        guard snapshot.status == .playing else { return nil }
        guard now - lastActivity <= Self.stallLimit else {
            pause(.executionInterrupted)
            return nil
        }
        return plan?.sample(at: baseElapsed + max(0, now - anchor))
    }

    mutating func confirm(_ sample: RouteTimingSample, at now: Double, writeStartedAt: Double? = nil) {
        guard snapshot.status == .playing || snapshot.status == .pausing else { return }
        confirmed = sample
        let previousDistance = plans.prefix(snapshot.segmentIndex).reduce(0) { $0 + $1.distance }
        snapshot.completedDistance = previousDistance + sample.distance
        snapshot.progress = snapshot.totalDistance > 0 ? min(1, snapshot.completedDistance / snapshot.totalDistance) : 1
        lastActivity = now
        if let writeStartedAt, now - writeStartedAt > Self.stallLimit {
            pause(.executionInterrupted)
        } else if snapshot.status == .pausing {
            pause(.user)
        } else if sample.finished {
            snapshot.status = nextSegmentIndex == nil ? .completed : .awaitingNextSegment
            snapshot.pauseReason = nil
            if snapshot.status == .completed { snapshot.progress = 1 }
        }
    }

    mutating func selectNextSegment() -> RoutePoint? {
        guard snapshot.status == .awaitingNextSegment, let next = nextSegmentIndex else { return nil }
        snapshot.segmentIndex = next
        snapshot.status = .idle
        snapshot.pauseReason = nil
        confirmed = nil
        baseElapsed = 0
        return plan?.points.first
    }

    /// Absolute future slot, skipping missed slots instead of replaying them.
    func nextDeadline(after now: Double) -> Double {
        let elapsed = max(0, now - anchor)
        return anchor + (floor(elapsed / Self.interval) + 1) * Self.interval
    }
}
