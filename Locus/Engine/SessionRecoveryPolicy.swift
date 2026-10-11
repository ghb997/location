import Foundation

struct RestorationRecord: Codable, Equatable, Sendable {
    var point: RoutePoint
    var pairingPath: String
    var deviceIP: String
}

/// A record is removed only after a confirmed clear. Neither a watchdog nor
/// transport reachability proves that locationd has restored its system fix.
final class RestorationRecordStore {
    static let defaultsKey = "locus.pendingLocationRestore"
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = RestorationRecordStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    var record: RestorationRecord? {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(RestorationRecord.self, from: data),
              Self.isValid(value) else { return nil }
        return value
    }

    var hasPendingRecord: Bool { defaults.object(forKey: key) != nil }

    @discardableResult
    func save(_ record: RestorationRecord) -> Bool {
        guard Self.isValid(record), let data = try? JSONEncoder().encode(record) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    func clear() { defaults.removeObject(forKey: key) }

    private static func isValid(_ value: RestorationRecord) -> Bool {
        RouteGeometry.isValid(value.point.coordinate) && TunnelConfig.isValidIP(value.deviceIP)
            && !value.pairingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct RetrySchedule: Equatable, Sendable {
    static let delays: [Double] = [1, 3, 8]
    private(set) var attempts = 0
    private(set) var isCancelled = false

    mutating func nextDelay() -> Double? {
        guard !isCancelled, attempts < Self.delays.count else { return nil }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }

    mutating func cancel() { isCancelled = true }
}

/// Invalidating movement also invalidates a background preparation result.
struct SessionOperationEpoch: Equatable, Sendable {
    private(set) var value = 0

    @discardableResult
    mutating func invalidate() -> Int {
        value &+= 1
        return value
    }

    func accepts(_ token: Int) -> Bool { token == value }
}
