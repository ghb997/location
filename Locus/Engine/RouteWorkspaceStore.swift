import Foundation

/// Serial persistence keeps large route encoding off MainActor. Small confirmed
/// checkpoints never re-encode the track. A playback ID binds each checkpoint
/// to its timing plan, including when the same track is started at a new speed.
final class RouteWorkspaceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.ghb997.location.route-store", qos: .utility)
    private let draftKey = "location.routeDraft.v1"
    private let routeKey = "location.routeArchive.v1"
    private let progressKey = "location.routeCheckpoint.v1"

    struct Loaded: Sendable {
        var draft: RouteTrack?
        var core: RoutePlaybackCore?
        var damaged = false
    }
    private struct DraftArchive: Codable { let version: Int; let track: RouteTrack }
    private struct Archive: Codable { let version: Int; let core: RoutePlaybackCore }
    private struct Checkpoint: Codable {
        let version: Int
        let playbackID: UUID
        let snapshot: RoutePlaybackSnapshot
        let confirmed: RouteTimingSample?
    }

    init(defaults: UserDefaults) { self.defaults = defaults }

    func saveDraft(_ track: RouteTrack?) {
        queue.async { [self] in
            if let track {
                guard Self.valid(track), let data = try? JSONEncoder().encode(DraftArchive(version: 1, track: track)),
                      data.count <= 12_000_000 else { return }
                defaults.set(data, forKey: draftKey)
            } else { defaults.removeObject(forKey: draftKey) }
        }
    }

    func saveRoute(_ core: RoutePlaybackCore?, includeArchive: Bool) {
        queue.async { [self] in
            guard let core else {
                defaults.removeObject(forKey: routeKey)
                defaults.removeObject(forKey: progressKey)
                return
            }
            if includeArchive {
                guard Self.valid(core.track), core.hasValidArchive,
                      let data = try? JSONEncoder().encode(Archive(version: 1, core: core)),
                      data.count <= 24_000_000 else { return }
                defaults.set(data, forKey: routeKey)
            }
            let checkpoint = Checkpoint(version: 1, playbackID: core.playbackID, snapshot: core.snapshot, confirmed: core.confirmed)
            if let data = try? JSONEncoder().encode(checkpoint) { defaults.set(data, forKey: progressKey) }
        }
    }

    func load() async -> Loaded {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                var loaded = Loaded()
                if defaults.object(forKey: draftKey) != nil {
                    if let data = defaults.data(forKey: draftKey), data.count <= 12_000_000,
                       let draft = try? JSONDecoder().decode(DraftArchive.self, from: data),
                       draft.version == 1, Self.valid(draft.track) {
                        loaded.draft = draft.track
                    } else { loaded.damaged = true }
                }
                if defaults.object(forKey: routeKey) != nil {
                    if let data = defaults.data(forKey: routeKey), data.count <= 24_000_000,
                       let archive = try? JSONDecoder().decode(Archive.self, from: data),
                       archive.version == 1, Self.valid(archive.core.track), archive.core.hasValidArchive {
                        var core = archive.core
                        if let progress = defaults.data(forKey: progressKey), progress.count <= 64_000,
                           let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: progress),
                           checkpoint.version == 1, checkpoint.playbackID == core.playbackID {
                            if !core.restoreCheckpoint(checkpoint.snapshot, confirmed: checkpoint.confirmed) {
                                loaded.damaged = true
                                core.prepareForReopen(resetProgress: true)
                            }
                        } else {
                            // An absent/mismatched checkpoint cannot authorize a jump.
                            loaded.damaged = true
                            core.prepareForReopen(resetProgress: true)
                        }
                        core.prepareForReopen()
                        loaded.core = core
                    } else { loaded.damaged = true }
                } else if defaults.object(forKey: progressKey) != nil { loaded.damaged = true }
                continuation.resume(returning: loaded)
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    private static func valid(_ track: RouteTrack) -> Bool {
        let count = track.segments.reduce(0) { $0 + $1.points.count }
        return count <= 50_000 && track.segments.count <= 50_000
            && Set(track.segments.map(\.id)).count == track.segments.count
            && track.segments.allSatisfy { $0.points.allSatisfy { RouteGeometry.isValid($0.coordinate) } }
    }
}
