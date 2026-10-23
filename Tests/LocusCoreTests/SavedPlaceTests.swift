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

    func testMissingAndLoadedEmptyAreDistinctFromCorruption() throws {
        try withDefaults { defaults in
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .missing)
            defaults.set(Data("[]".utf8), forKey: "favorites")
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .loaded([]))
            defaults.set(Data("[broken".utf8), forKey: "favorites")
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .corrupt(.malformedData))
        }
    }

    func testAddingAfterCompatibilityLoadCannotOverwriteCorruptSourceOrItsBackup() throws {
        try withDefaults { defaults in
            let damaged = Data("[ {\"name\": \"my damaged saved place\"}".utf8)
            defaults.set(damaged, forKey: "favorites")
            var visiblePlaces = SavedPlace.load(key: "favorites", defaults: defaults)
            XCTAssertTrue(visiblePlaces.isEmpty)
            visiblePlaces.append(SavedPlace(name: "New", latitude: 30, longitude: 120))
            XCTAssertFalse(SavedPlace.save(visiblePlaces, key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: "favorites"), damaged)
            XCTAssertEqual(defaults.data(forKey: SavedPlace.corruptBackupKey(for: "favorites")), damaged)
            XCTAssertEqual(SavedPlace.rawDataForExport(key: "favorites", defaults: defaults), damaged)
            XCTAssertNil(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults))
            XCTAssertFalse(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: "favorites"), damaged)
        }
    }

    func testCorruptionAfterLoadingIsCheckedAgainBeforeEveryWrite() throws {
        try withDefaults { defaults in
            let saved = SavedPlace(name: "Saved", latitude: 30, longitude: 120)
            XCTAssertTrue(SavedPlace.save([saved], key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), [saved])
            let damaged = Data("not JSON".utf8)
            defaults.set(damaged, forKey: "favorites")
            XCTAssertFalse(SavedPlace.save([], key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: "favorites"), damaged)
            XCTAssertEqual(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults), [saved])
        }
    }

    func testExplicitRecoveryRestoresValidatedLatestDataAndKeepsEveryDamagedSample() throws {
        try withDefaults { defaults in
            let first = SavedPlace(name: "First", latitude: 30, longitude: 120)
            let latest = SavedPlace(name: "Latest", latitude: 31, longitude: 121)
            XCTAssertTrue(SavedPlace.save([first], key: "favorites", defaults: defaults))
            XCTAssertTrue(SavedPlace.save([first, latest], key: "favorites", defaults: defaults))
            let damaged = Data("damaged original".utf8)
            defaults.set(damaged, forKey: "favorites")
            XCTAssertEqual(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults), [first, latest])
            XCTAssertTrue(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), [first, latest])
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), damaged)

            let laterDamage = Data("another damaged original".utf8)
            defaults.set(laterDamage, forKey: "favorites")
            XCTAssertTrue(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: SavedPlace.corruptBackupKey(for: "favorites")), damaged)
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), laterDamage)
            XCTAssertTrue(SavedPlace.save([latest], key: "favorites", defaults: defaults))
        }
    }

    func testRecoveryRejectsBrokenBackupAndFallsBackToExactLegacyMigrationBackup() throws {
        try withDefaults { defaults in
            let original = Data("[ {\"name\":\"Old\",\"latitude\":39.9,\"longitude\":116.4} ]".utf8)
            defaults.set(original, forKey: "favorites")
            let migrated = SavedPlace.load(key: "favorites", defaults: defaults)
            let damaged = Data("broken source".utf8)
            defaults.set(damaged, forKey: "favorites")
            defaults.set(Data("broken backup".utf8), forKey: SavedPlace.lastKnownGoodBackupKey(for: "favorites"))
            XCTAssertTrue(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), migrated)
            XCTAssertEqual(defaults.data(forKey: SavedPlace.legacyBackupKey(for: "favorites")), original)
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), damaged)

            defaults.set(damaged, forKey: "favorites")
            defaults.set(Data("[] trailing content".utf8), forKey: SavedPlace.lastKnownGoodBackupKey(for: "favorites"))
            defaults.set(Data("not a backup".utf8), forKey: SavedPlace.legacyBackupKey(for: "favorites"))
            XCTAssertNil(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults))
            XCTAssertFalse(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: "favorites"), damaged)
        }
    }

    func testFutureSchemaIsPreservedAndCannotBeRestoredOrSilentlyDowngraded() throws {
        try withDefaults { defaults in
            let future = Data("[{\"id\":\"future-id\",\"name\":\"Future\",\"latitude\":30,\"longitude\":120,\"source\":\"manual\",\"coordinateSystem\":\"wgs84\",\"schemaVersion\":99}]".utf8)
            defaults.set(future, forKey: "favorites")
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .corrupt(.unsupportedSchema(99)))
            XCTAssertFalse(SavedPlace.save([], key: "favorites", defaults: defaults))
            defaults.set(future, forKey: SavedPlace.lastKnownGoodBackupKey(for: "favorites"))
            XCTAssertNil(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults))
            XCTAssertFalse(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: "favorites"), future)
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), future)
        }
    }

    func testInvalidCoordinatesIdentityAndSourceAreRejectedWithoutPartialMigration() throws {
        try withDefaults { defaults in
            let invalidRows: [(String, SavedPlace.StorageIssue)] = [
                ("{\"name\":\"Invalid\",\"latitude\":91,\"longitude\":120}", .invalidCoordinate),
                ("{\"name\":\"Invalid\",\"latitude\":30,\"longitude\":181}", .invalidCoordinate),
                ("{\"id\":\"  \",\"name\":\"Invalid\",\"latitude\":30,\"longitude\":120}", .invalidIdentity),
                ("{\"name\":\"Invalid\",\"latitude\":30,\"longitude\":120,\"source\":\"unknown\"}", .invalidSource),
                ("{\"name\":\"Invalid\",\"latitude\":30,\"longitude\":120,\"originalCoordinate\":{\"latitude\":-91,\"longitude\":120}}", .invalidOriginalCoordinate)
            ]
            for (invalid, issue) in invalidRows {
                let data = Data("[{\"name\":\"Valid\",\"latitude\":30,\"longitude\":120},\(invalid)]".utf8)
                defaults.set(data, forKey: "favorites")
                XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .corrupt(issue))
                XCTAssertFalse(SavedPlace.save([], key: "favorites", defaults: defaults))
                XCTAssertEqual(defaults.data(forKey: "favorites"), data)
                XCTAssertNil(defaults.object(forKey: SavedPlace.legacyBackupKey(for: "favorites")))
            }
        }
    }

    func testDuplicateIDsAndInvalidWriteCannotReplaceValidSavedPlaces() throws {
        try withDefaults { defaults in
            let first = SavedPlace(name: "First", latitude: 30, longitude: 120, id: "stable")
            let duplicate = SavedPlace(name: "Other", latitude: 31, longitude: 121, id: "stable")
            XCTAssertTrue(SavedPlace.save([first], key: "favorites", defaults: defaults))
            let original = defaults.data(forKey: "favorites")
            for invalid in [duplicate, SavedPlace(name: "NaN", latitude: .nan, longitude: 120), SavedPlace(name: "Outside", latitude: 30, longitude: 190)] {
                XCTAssertFalse(SavedPlace.save([first, invalid], key: "favorites", defaults: defaults))
                XCTAssertEqual(defaults.data(forKey: "favorites"), original)
            }
            let duplicatedData = try JSONEncoder().encode([first, duplicate])
            defaults.set(duplicatedData, forKey: "favorites")
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .corrupt(.duplicateIdentity))
            XCTAssertTrue(SavedPlace.restoreBackup(key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), [first])
        }
    }

    func testUnexpectedPreferenceTypeIsPreservedAndExportableInsteadOfTreatedAsMissing() throws {
        try withDefaults { defaults in
            defaults.set(["unexpected": "original user data"], forKey: "favorites")
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .corrupt(.malformedData))
            XCTAssertFalse(SavedPlace.save([], key: "favorites", defaults: defaults))
            XCTAssertEqual(defaults.dictionary(forKey: "favorites") as? [String: String], ["unexpected": "original user data"])
            let export = try XCTUnwrap(SavedPlace.rawDataForExport(key: "favorites", defaults: defaults))
            let propertyList = try XCTUnwrap(try PropertyListSerialization.propertyList(from: export, options: [], format: nil) as? [String: [String: String]])
            XCTAssertEqual(propertyList["storedValue"], ["unexpected": "original user data"])
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), export)
        }
    }

    func testExplicitFreshListKeepsDamagedBytesAfterLaterSuccessfulWrites() throws {
        try withDefaults { defaults in
            let damaged = Data("original damaged bytes, including saved coordinates".utf8)
            defaults.set(damaged, forKey: "favorites")
            XCTAssertNil(SavedPlace.recoverableBackup(key: "favorites", defaults: defaults))
            XCTAssertTrue(SavedPlace.startNewListPreservingDamagedData(key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.loadResult(key: "favorites", defaults: defaults), .loaded([]))
            let replacement = SavedPlace(name: "New list", latitude: 30, longitude: 120)
            XCTAssertTrue(SavedPlace.save([replacement], key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), [replacement])
            XCTAssertEqual(SavedPlace.preservedCorruptData(key: "favorites", defaults: defaults), damaged)
            XCTAssertEqual(defaults.data(forKey: SavedPlace.corruptBackupKey(for: "favorites")), damaged)
            // A stale confirmation must not erase a list that became healthy.
            XCTAssertFalse(SavedPlace.startNewListPreservingDamagedData(key: "favorites", defaults: defaults))
            XCTAssertEqual(SavedPlace.load(key: "favorites", defaults: defaults), [replacement])
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "LocusSavedPlaceRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
