import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

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
        name = try values.decode(String.self, forKey: .name)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        // Old rows already identified themselves by these exact numeric values.
        // Preserve that identity once; save it explicitly during migration.
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? "\(latitude),\(longitude)"
        let rawSource = try values.decodeIfPresent(String.self, forKey: .source)
        source = rawSource.flatMap(CoordinateSource.init(rawValue:)) ?? .legacy
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        originalCoordinate = try values.decodeIfPresent(OriginalCoordinate.self, forKey: .originalCoordinate)
        // Stored v2 data is already normalized. Refuse a mislabeled datum
        // instead of interpreting it again when a settings toggle changes.
        if let datum = try values.decodeIfPresent(String.self, forKey: .coordinateSystem), datum != CoordinateSystem.wgs84.rawValue {
            throw DecodingError.dataCorruptedError(forKey: .coordinateSystem, in: values, debugDescription: "Stored places must use WGS84 coordinates.")
        }
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

    static func load(key: String, defaults: UserDefaults = .standard) -> [SavedPlace] {
        guard let data = defaults.data(forKey: key),
              var decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else { return [] }
        if decoded.contains(where: { $0.schemaVersion < currentSchemaVersion }) {
            let backupKey = legacyBackupKey(for: key)
            if defaults.data(forKey: backupKey) == nil { defaults.set(data, forKey: backupKey) }
            for index in decoded.indices { decoded[index].schemaVersion = currentSchemaVersion }
            save(decoded, key: key, defaults: defaults)
        }
        return decoded
    }

    @discardableResult
    static func save(_ places: [SavedPlace], key: String, defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(places) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
