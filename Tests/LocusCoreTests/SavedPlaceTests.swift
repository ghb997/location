import Foundation
import XCTest
@testable import LocusCore

final class SavedPlaceTests: XCTestCase {
    func testMigrationBacksUpExactLegacyDataWithoutMovingOrRenamingPlaces() throws {
        let suite = "LocusSavedPlaceMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "favorites"
        let original = Data("[{\"name\":\"旧地点\",\"latitude\":39.90940335390724,\"longitude\":116.40324337854781}]".utf8)
        defaults.set(original, forKey: key)
        let migrated = try XCTUnwrap(SavedPlace.load(key: key, defaults: defaults).first)
        XCTAssertEqual(defaults.data(forKey: SavedPlace.legacyBackupKey(for: key)), original)
        XCTAssertEqual(migrated.name, "旧地点")
        XCTAssertEqual(migrated.latitude, 39.90940335390724)
        XCTAssertEqual(migrated.longitude, 116.40324337854781)
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertTrue(migrated.isLegacy)
        let firstMigration = defaults.data(forKey: key)
        defaults.set(CoordinateSystem.gcj02.rawValue, forKey: CoordinateSettings.mapKey)
        XCTAssertEqual(SavedPlace.load(key: key, defaults: defaults).first, migrated)
        XCTAssertEqual(defaults.data(forKey: key), firstMigration)
        XCTAssertEqual(defaults.data(forKey: SavedPlace.legacyBackupKey(for: key)), original)
    }

    func testExplicitLegacyCorrectionKeepsIdentityAndCanBeUndoneAfterReload() throws {
        let original = try JSONDecoder().decode(SavedPlace.self, from: Data("{\"name\":\"Beijing\",\"latitude\":39.90940335390724,\"longitude\":116.40324337854781}".utf8))
        let corrected = try original.correctedFromGCJ02()
        XCTAssertEqual(corrected.id, original.id)
        XCTAssertEqual(corrected.name, original.name)
        XCTAssertEqual(corrected.latitude, 39.908, accuracy: 1e-7)
        XCTAssertEqual(corrected.longitude, 116.397, accuracy: 1e-7)
        XCTAssertTrue(corrected.canRestore)
        XCTAssertFalse(corrected.isLegacy)
        XCTAssertThrowsError(try corrected.correctedFromGCJ02())
        let reloaded = try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(corrected))
        let restored = reloaded.restoringOriginalCoordinate()
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.latitude, original.latitude)
        XCTAssertEqual(restored.longitude, original.longitude)
        XCTAssertFalse(restored.canRestore)
        XCTAssertTrue(restored.isLegacy)
    }

    func testNewStandardPlaceCannotBeInterpretedAgainAsLegacyGCJ02() throws {
        let standard = SavedPlace(name: "GPS", latitude: 39.908, longitude: 116.397, source: .gpx)
        let reloaded = try JSONDecoder().decode(SavedPlace.self, from: JSONEncoder().encode(standard))
        XCTAssertEqual(reloaded, standard)
        XCTAssertFalse(reloaded.isLegacy)
        XCTAssertThrowsError(try reloaded.correctedFromGCJ02())
        XCTAssertEqual(reloaded.restoringOriginalCoordinate(), reloaded)
    }

    func testExcludedLegacyPointIsKeptAndCannotReceiveCorrection() throws {
        let hongKong = try JSONDecoder().decode(SavedPlace.self, from: Data("{\"name\":\"Hong Kong\",\"latitude\":22.3193,\"longitude\":114.1694}".utf8))
        XCTAssertThrowsError(try hongKong.correctedFromGCJ02())
        XCTAssertEqual(hongKong.latitude, 22.3193)
    }

    func testCoordinateDeduplicationDoesNotDependOnStableRowIdentity() {
        let first = SavedPlace(name: "A", latitude: 30, longitude: 120)
        let second = SavedPlace(name: "B", latitude: 30, longitude: 120)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.coordinateKey, second.coordinateKey)
    }

    func testStoredNonstandardDatumIsRejectedInsteadOfConvertedTwice() {
        let data = Data("{\"name\":\"Incorrect datum\",\"latitude\":39.9,\"longitude\":116.4,\"coordinateSystem\":\"gcj02\",\"schemaVersion\":2}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedPlace.self, from: data))
    }
}
