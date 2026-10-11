import CoreLocation
import Foundation
import XCTest
@testable import LocusCore

final class CoordinateTransformTests: XCTestCase {
    // Fixed outputs from the unmodified coordtransform 2.1.2 JavaScript at
    // 606c6f3b57b6f1d60458793fea39928d2b11b637, not computed by Swift under test.
    private let referencePoints: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = [
        (.init(latitude: 39.908, longitude: 116.397), .init(latitude: 39.90940335390724, longitude: 116.40324337854781)),
        (.init(latitude: 31.2304, longitude: 121.4737), .init(latitude: 31.22845773757727, longitude: 121.47822305927693)),
        (.init(latitude: 23.1291, longitude: 113.2644), .init(latitude: 23.126423339922844, longitude: 113.26972959210308)),
        (.init(latitude: 30.5728, longitude: 104.0665), .init(latitude: 30.570345719673213, longitude: 104.06900492845789)),
        (.init(latitude: 20.044, longitude: 110.1983), .init(latitude: 20.04188856033355, longitude: 110.2025950072095))
    ]

    func testForwardTransformMatchesPinnedUpstreamReference() throws {
        for (standard, expected) in referencePoints {
            let converted = try CoordinateTransform.convert(standard, from: .wgs84, to: .gcj02)
            assertEqual(converted, expected, accuracy: 1e-10)
        }
    }

    func testIterativeInverseReturnsReferenceWGS84() throws {
        for (standard, gcj) in referencePoints {
            let restored = try CoordinateTransform.normalize(gcj, from: .gcj02)
            assertEqual(restored, standard, accuracy: 1e-7)
        }
    }

    func testStandardCoordinatesNeverReceiveAnOffset() throws {
        for (standard, _) in referencePoints {
            assertEqual(try CoordinateTransform.normalize(standard, from: .wgs84), standard, accuracy: 0)
        }
    }

    func testCoverageIncludesHainanAndExcludesOtherMapUnitsAndNeighbors() throws {
        for (standard, _) in referencePoints { XCTAssertTrue(try OfflineMainlandCoverage.contains(standard)) }
        let excluded: [CLLocationCoordinate2D] = [
            .init(latitude: 22.3193, longitude: 114.1694), // Hong Kong
            .init(latitude: 22.1987, longitude: 113.5439), // Macau
            .init(latitude: 25.033, longitude: 121.5654), // Taiwan
            .init(latitude: 37.5665, longitude: 126.978), // Korea: inside the old rectangle
            .init(latitude: 21.0285, longitude: 105.8542), // Vietnam: inside the old rectangle
            .init(latitude: 13.7563, longitude: 100.5018), // Thailand: inside the old rectangle
            .init(latitude: 47.6062, longitude: -122.3321)
        ]
        for coordinate in excluded {
            XCTAssertFalse(try OfflineMainlandCoverage.contains(coordinate))
            assertEqual(try CoordinateTransform.convert(coordinate, from: .wgs84, to: .gcj02), coordinate, accuracy: 0)
            assertEqual(try CoordinateTransform.normalize(coordinate, from: .gcj02), coordinate, accuracy: 0)
        }
    }

    func testInvalidValuesAreRejectedBeforeEitherConversionOrPassThrough() {
        let invalid: [CLLocationCoordinate2D] = [
            .init(latitude: .nan, longitude: 116), .init(latitude: 39, longitude: .infinity),
            .init(latitude: 91, longitude: 116), .init(latitude: 39, longitude: 181)
        ]
        for coordinate in invalid {
            XCTAssertThrowsError(try CoordinateTransform.normalize(coordinate, from: .wgs84))
            XCTAssertThrowsError(try CoordinateTransform.normalize(coordinate, from: .gcj02))
        }
    }

    func testMapAndServiceConventionsAreIndependentAndDefaultToStandard() throws {
        let suite = "LocusCoordinateSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (standard, gcj) = referencePoints[0]
        assertEqual(try CoordinateSettings.mapOutput(standard, defaults: defaults), standard, accuracy: 0)
        defaults.set(CoordinateSystem.gcj02.rawValue, forKey: CoordinateSettings.mapKey)
        assertEqual(try CoordinateSettings.mapOutput(standard, defaults: defaults), gcj, accuracy: 1e-10)
        assertEqual(try CoordinateSettings.mapInput(gcj, defaults: defaults), standard, accuracy: 1e-7)
        assertEqual(try CoordinateSettings.serviceInput(standard, defaults: defaults), standard, accuracy: 0)
        defaults.set(CoordinateSystem.gcj02.rawValue, forKey: CoordinateSettings.serviceKey)
        assertEqual(try CoordinateSettings.serviceInput(standard, defaults: defaults), gcj, accuracy: 1e-10)
        assertEqual(try CoordinateSettings.serviceOutput(gcj, defaults: defaults), standard, accuracy: 1e-7)
        defaults.set("unsupported", forKey: CoordinateSettings.mapKey)
        XCTAssertEqual(CoordinateSettings.mapSystem(defaults: defaults), .wgs84)
    }

    func testStandardGPXRoundTripRemainsStandardAndOverrideIsExplicit() throws {
        let (standard, gcj) = referencePoints[0]
        let standardData = Data(GPXCodec.export([standard]).utf8)
        let importedStandard = try XCTUnwrap(GPXCodec.parse(data: standardData).first)
        assertEqual(importedStandard, standard, accuracy: 1e-8)
        let nonstandardData = Data(GPXCodec.export([gcj]).utf8)
        let importedRaw = try XCTUnwrap(GPXCodec.parse(data: nonstandardData).first)
        assertEqual(importedRaw, gcj, accuracy: 1e-8)
        let corrected = try CoordinateTransform.normalize(importedRaw, from: .gcj02)
        let reimported = try XCTUnwrap(GPXCodec.parse(data: Data(GPXCodec.export([corrected]).utf8)).first)
        assertEqual(reimported, standard, accuracy: 1e-7)
    }

    private func assertEqual(_ actual: CLLocationCoordinate2D, _ expected: CLLocationCoordinate2D, accuracy: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.latitude, expected.latitude, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.longitude, expected.longitude, accuracy: accuracy, file: file, line: line)
    }
}
