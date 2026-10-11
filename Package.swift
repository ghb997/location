// swift-tools-version: 5.9
import PackageDescription

// Device-independent state, timing, file and coordinate regressions run on macOS.
let package = Package(
    name: "LocusCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LocusCore", targets: ["LocusCore"])],
    targets: [
        .target(
            name: "LocusCore",
            path: "Locus",
            exclude: [
                "App",
                "Features",
                "Resources/en.lproj",
                "Resources/zh-Hans.lproj",
                "Resources/Info.plist",
                "Resources/Locus.entitlements",
                "Engine/BackgroundKeepAlive.swift",
                "Engine/LocationEngine.swift",
                "Engine/NativeLocationTransport.swift",
                "Engine/PairableHostAdvertiser.swift",
                "Engine/PairingStore.swift",
                "Engine/PairOnDeviceService.swift",
                "Engine/RouteBuilder.swift",
                "Engine/SilentAudioKeepAlive.swift",
                "Engine/SpoofSession.swift",
                "Engine/TunnelDiagnostics.swift",
                "Support/IconButton.swift",
                "Support/LocalDevVPN.swift",
                "Support/PairingDocumentPicker.swift",
                "Support/Theme.swift"
            ],
            sources: [
                "Engine/GPXCodec.swift",
                "Engine/RouteGeometry.swift",
                "Engine/PairingFileValidator.swift",
                "Engine/DeviceTunnel.swift",
                "Support/L10n.swift",
                "Engine/RouteDocument.swift",
                "Engine/RoutePlaybackCore.swift",
                "Engine/PlaybackClock.swift",
                "Engine/TunnelPolicy.swift",
                "Engine/NativeOperationPolicy.swift",
                "Engine/NativeRequestControl.swift",
                "Engine/PairingAttemptPolicy.swift",
                "Engine/TunnelPreparationPolicy.swift",
                "Engine/LatestOperation.swift",
                "Engine/SessionRecoveryPolicy.swift",
                "Engine/LocationTransport.swift",
                "Engine/CoordinateTransform.swift",
                "Engine/OfflineMainlandCoverage.swift",
                "Support/CoordinateSettings.swift",
                "Support/SavedPlace.swift"
            ],
            resources: [.process("Resources/CoordinateData")]
        ),
        .testTarget(name: "LocusCoreTests", dependencies: ["LocusCore"], path: "Tests/LocusCoreTests")
    ]
)
