// swift-tools-version: 5.9
import PackageDescription

// Core regression tests run on macOS without linking the device-only idevice FFI.
let package = Package(
    name: "LocusCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LocusCore", targets: ["LocusCore"])],
    targets: [
        .target(
            name: "LocusCore",
            path: "Locus",
            exclude: [
                "App", "Features", "Resources",
                "Engine/BackgroundKeepAlive.swift", "Engine/LocationEngine.swift",
                "Engine/PairOnDeviceService.swift", "Engine/PairableHostAdvertiser.swift",
                "Engine/PairingStore.swift", "Engine/RouteBuilder.swift",
                "Engine/SilentAudioKeepAlive.swift", "Engine/SpoofSession.swift",
                "Support/LocalDevVPN.swift", "Support/PairingDocumentPicker.swift",
                "Support/SavedPlace.swift", "Support/Theme.swift", "Support/IconButton.swift"
            ],
            sources: [
                "Engine/GPXCodec.swift", "Engine/RouteGeometry.swift",
                "Engine/PairingFileValidator.swift", "Engine/DeviceTunnel.swift", "Support/L10n.swift"
            ]
        ),
        .testTarget(name: "LocusCoreTests", dependencies: ["LocusCore"], path: "Tests/LocusCoreTests")
    ]
)
