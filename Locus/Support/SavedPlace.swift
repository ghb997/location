import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

    /// A failed read must never look like a successfully loaded empty list to
    /// code deciding whether it is safe to replace the persisted data.
    enum LoadResult: Equatable {
        case missing
        case loaded([SavedPlace])
        case corrupt(StorageIssue)

        var places: [SavedPlace] {
            if case let .loaded(places) = self { return places }
            return []
        }

        var requiresRecovery: Bool {
            if case .corrupt = self { return true }
            return false
        }
    }

    enum StorageIssue: Error, Equatable {
        case malformedData
        case unsupportedSchema(Int)
        case invalidCoordinate
        case invalidIdentity
        case duplicateIdentity
        case invalidSource
        case invalidDatum
        case invalidOriginalCoordinate
    }

    // Keep validation, backup and replacement indivisible for callers sharing
    // this process. UserDefaults remains the existing storage boundary.
    private static let storageLock = NSRecursiveLock()

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var source: CoordinateSource
    private(set) var schemaVersion: Int
    private(set) var originalCoordinate: OriginalCoordinate?

    struct OriginalCoordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
    }

    /// Coordinate identity is separate from UI identity: editing/restoring a
    /// point must not change its row ID, while callers can still deduplicate.
    var coordinateKey: String { "\(latitude),\(longitude)" }
    var isLegacy: Bool { source == .legacy && originalCoordinate == nil }
    var canRestore: Bool { originalCoordinate != nil }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, latitude: Double, longitude: Double, source: CoordinateSource = .manual, id: String = UUID().uuidString) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
        schemaVersion = Self.currentSchemaVersion
        originalCoordinate = nil
    }

    /// This operation is explicit and only available for uncorrected legacy
    /// values, whose original datum cannot be recovered from the old schema.
    func correctedFromGCJ02() throws -> SavedPlace {
        guard isLegacy else { throw CoordinateTransformError.alreadyCorrected }
        guard try OfflineMainlandCoverage.contains(coordinate) else { throw CoordinateTransformError.outsideCoverage }
        let standard = try CoordinateTransform.normalize(coordinate, from: .gcj02)
        guard standard.latitude != latitude || standard.longitude != longitude else {
            throw CoordinateTransformError.outsideCoverage
        }
        var corrected = self
        corrected.originalCoordinate = OriginalCoordinate(latitude: latitude, longitude: longitude)
        corrected.latitude = standard.latitude
        corrected.longitude = standard.longitude
        return corrected
    }

    func restoringOriginalCoordinate() -> SavedPlace {
        guard let original = originalCoordinate else { return self }
        var restored = self
        restored.latitude = original.latitude
        restored.longitude = original.longitude
        restored.originalCoordinate = nil
        return restored
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, source, schemaVersion, coordinateSystem, originalCoordinate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw StorageIssue.unsupportedSchema(schemaVersion)
        }
        name = try values.decode(String.self, forKey: .name)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        // Old rows already identified themselves by these exact numeric values.
        // Preserve that identity once; save it explicitly during migration.
        let storedID = try values.decodeIfPresent(String.self, forKey: .id)
        if schemaVersion >= 2 && storedID == nil { throw StorageIssue.invalidIdentity }
        id = storedID ?? "\(latitude),\(longitude)"
        let rawSource = try values.decodeIfPresent(String.self, forKey: .source)
        if let rawSource {
            guard let knownSource = CoordinateSource(rawValue: rawSource) else { throw StorageIssue.invalidSource }
            source = knownSource
        } else {
            guard schemaVersion == 1 else { throw StorageIssue.invalidSource }
            source = .legacy
        }
        originalCoordinate = try values.decodeIfPresent(OriginalCoordinate.self, forKey: .originalCoordinate)
        // Stored v2 data is already normalized. Refuse a mislabeled datum
        // instead of interpreting it again when a settings toggle changes.
        let datum = try values.decodeIfPresent(String.self, forKey: .coordinateSystem)
        if (schemaVersion >= 2 && datum == nil) || (datum != nil && datum != CoordinateSystem.wgs84.rawValue) {
            throw StorageIssue.invalidDatum
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        try values.encode(source.rawValue, forKey: .source)
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(CoordinateSystem.wgs84.rawValue, forKey: .coordinateSystem)
        try values.encodeIfPresent(originalCoordinate, forKey: .originalCoordinate)
    }

    static func legacyBackupKey(for key: String) -> String { key + ".legacyBackup.v1" }
    static func lastKnownGoodBackupKey(for key: String) -> String { key + ".lastKnownGood.v2" }
    static func corruptBackupKey(for key: String) -> String { key + ".corruptBackup.v1" }
    private static func corruptArchiveKey(for key: String) -> String { key + ".corruptArchive.v1" }

    /// Compatibility for callers that only display rows. Mutations must still
    /// go through save(), which independently checks the persisted source.
    static func load(key: String, defaults: UserDefaults = .standard) -> [SavedPlace] {
        loadResult(key: key, defaults: defaults).places
    }

    static func loadResult(key: String, defaults: UserDefaults = .standard) -> LoadResult {
        withStorageLock {
            let result = readSource(key: key, defaults: defaults)
            guard case let .loaded(places) = result, let original = defaults.data(forKey: key) else { return result }
            var upgraded = places
            if places.contains(where: { $0.schemaVersion < currentSchemaVersion }) {
                preserveLegacyData(original, key: key, defaults: defaults)
                for index in upgraded.indices { upgraded[index].schemaVersion = currentSchemaVersion }
                guard let data = try? JSONEncoder().encode(upgraded) else { return .corrupt(.malformedData) }
                defaults.set(data, forKey: key)
                defaults.set(data, forKey: lastKnownGoodBackupKey(for: key))
            } else if defaults.data(forKey: lastKnownGoodBackupKey(for: key)) != original {
                // Existing installations receive a recovery copy on their
                // first successful read, before the first edit is necessary.
                defaults.set(original, forKey: lastKnownGoodBackupKey(for: key))
            }
            return .loaded(upgraded)
        }
    }

    @discardableResult
    static func save(_ places: [SavedPlace], key: String, defaults: UserDefaults = .standard) -> Bool {
        withStorageLock {
            let current = readSource(key: key, defaults: defaults)
            guard !current.requiresRecovery,
                  (try? validate(places)) != nil,
                  let data = try? JSONEncoder().encode(places) else { return false }
            if case let .loaded(previous) = current,
               previous.contains(where: { $0.schemaVersion < currentSchemaVersion }),
               let original = defaults.data(forKey: key) {
                preserveLegacyData(original, key: key, defaults: defaults)
            }
            defaults.set(data, forKey: lastKnownGoodBackupKey(for: key))
            defaults.set(data, forKey: key)
            return true
        }
    }

    /// A corrupt or future-version backup is never a recovery candidate. The
    /// untouched migration backup is a fallback if the recent copy is damaged.
    static func recoverableBackup(key: String, defaults: UserDefaults = .standard) -> [SavedPlace]? {
        withStorageLock { validBackup(key: key, defaults: defaults)?.places }
    }

    /// This is the only operation permitted to replace a corrupt source. It is
    /// explicit, validates the backup, and archives the damaged bytes first.
    @discardableResult
    static func restoreBackup(key: String, defaults: UserDefaults = .standard) -> Bool {
        withStorageLock {
            guard let backup = validBackup(key: key, defaults: defaults) else { return false }
            _ = readSource(key: key, defaults: defaults)
            var restored = backup.places
            if restored.contains(where: { $0.schemaVersion < currentSchemaVersion }) {
                preserveLegacyData(backup.data, key: key, defaults: defaults)
                for index in restored.indices { restored[index].schemaVersion = currentSchemaVersion }
            }
            guard let data = try? JSONEncoder().encode(restored) else { return false }
            defaults.set(data, forKey: lastKnownGoodBackupKey(for: key))
            defaults.set(data, forKey: key)
            return true
        }
    }

    /// Call only after the user explicitly chooses to create a fresh list. A
    /// healthy list cannot be reset through this recovery-only operation.
    @discardableResult
    static func startNewListPreservingDamagedData(key: String, defaults: UserDefaults = .standard) -> Bool {
        withStorageLock {
            guard readSource(key: key, defaults: defaults).requiresRecovery,
                  let damaged = rawData(key: key, defaults: defaults),
                  preservedCorruptData(key: key, defaults: defaults) == damaged else { return false }
            let empty = Data("[]".utf8)
            defaults.set(empty, forKey: lastKnownGoodBackupKey(for: key))
            defaults.set(empty, forKey: key)
            return true
        }
    }

    /// Original JSON is returned byte for byte. An unexpected UserDefaults
    /// value is exported as a property-list envelope without dropping fields.
    /// Raw exports may contain the user's saved coordinates and names, and are
    /// separate from the redacted diagnostics export.
    static func rawDataForExport(key: String, defaults: UserDefaults = .standard) -> Data? {
        withStorageLock {
            rawData(key: key, defaults: defaults) ?? preservedCorruptData(key: key, defaults: defaults)
        }
    }

    static func preservedCorruptData(key: String, defaults: UserDefaults = .standard) -> Data? {
        withStorageLock {
            let archived = defaults.array(forKey: corruptArchiveKey(for: key)) as? [Data]
            return archived?.last ?? defaults.data(forKey: corruptBackupKey(for: key))
        }
    }

    private func validate() throws {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else { throw StorageIssue.unsupportedSchema(schemaVersion) }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StorageIssue.invalidIdentity }
        guard Self.validCoordinate(latitude: latitude, longitude: longitude) else { throw StorageIssue.invalidCoordinate }
        if let originalCoordinate {
            guard source == .legacy,
                  Self.validCoordinate(latitude: originalCoordinate.latitude, longitude: originalCoordinate.longitude) else {
                throw StorageIssue.invalidOriginalCoordinate
            }
        }
    }

    private static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private static func validate(_ places: [SavedPlace]) throws {
        var identities = Set<String>()
        for place in places {
            try place.validate()
            guard identities.insert(place.id).inserted else { throw StorageIssue.duplicateIdentity }
        }
    }

    private static func decode(_ data: Data) throws -> [SavedPlace] {
        let places = try JSONDecoder().decode([SavedPlace].self, from: data)
        try validate(places)
        return places
    }

    private static func readSource(key: String, defaults: UserDefaults) -> LoadResult {
        guard defaults.object(forKey: key) != nil else { return .missing }
        do {
            guard let data = defaults.data(forKey: key) else { throw StorageIssue.malformedData }
            return .loaded(try decode(data))
        } catch {
            if let raw = rawData(key: key, defaults: defaults) {
                // Never replace the first damaged sample; retain later samples
                // as well, including across successful recovery. Repeated reads
                // of the same damaged source do not grow the archive.
                if defaults.object(forKey: corruptBackupKey(for: key)) == nil {
                    defaults.set(raw, forKey: corruptBackupKey(for: key))
                }
                var archive = defaults.array(forKey: corruptArchiveKey(for: key)) as? [Data] ?? []
                if archive.last != raw {
                    archive.append(raw)
                    defaults.set(archive, forKey: corruptArchiveKey(for: key))
                }
            }
            return .corrupt(error as? StorageIssue ?? .malformedData)
        }
    }

    private static func preserveLegacyData(_ data: Data, key: String, defaults: UserDefaults) {
        let backupKey = legacyBackupKey(for: key)
        if defaults.object(forKey: backupKey) == nil { defaults.set(data, forKey: backupKey) }
    }

    private static func validBackup(key: String, defaults: UserDefaults) -> (data: Data, places: [SavedPlace])? {
        for backupKey in [lastKnownGoodBackupKey(for: key), legacyBackupKey(for: key)] {
            if let data = defaults.data(forKey: backupKey), let places = try? decode(data) {
                return (data, places)
            }
        }
        return nil
    }

    private static func rawData(key: String, defaults: UserDefaults) -> Data? {
        guard let object = defaults.object(forKey: key) else { return nil }
        if let data = object as? Data { return data }
        return try? PropertyListSerialization.data(fromPropertyList: ["storedValue": object], format: .xml, options: 0)
    }

    private static func withStorageLock<T>(_ body: () -> T) -> T {
        storageLock.lock()
        defer { storageLock.unlock() }
        return body()
    }
}
