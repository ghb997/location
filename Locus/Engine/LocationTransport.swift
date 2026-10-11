import Foundation

enum LocationEngineError: LocalizedError, Equatable {
    case invalidCoordinate, invalidIP, pairingRead, tunnelCreate, remoteServer
    case simulationCreate, locationSet, locationClear, notActive
    case operationCancelled, operationTimedOut, operationBusy, serviceUnreachable, localNetworkDenied

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: return L10n.tr("Coordinates must be finite, with latitude from −90 to 90 and longitude from −180 to 180.")
        case .invalidIP: return L10n.tr("Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1).")
        case .pairingRead: return L10n.tr("Could not read the RPPairing file. Generate one with idevice_pair in RPPairing mode.")
        case .tunnelCreate: return L10n.tr("Could not open the developer tunnel. Check the pairing record and the RemotePairing endpoint.")
        case .remoteServer: return L10n.tr("Connected to the tunnel but RemoteXPC handshake failed.")
        case .simulationCreate: return L10n.tr("Could not open Apple’s location simulation service.")
        case .locationSet: return L10n.tr("Failed to set simulated coordinates.")
        case .locationClear: return L10n.tr("Failed to clear simulated location.")
        case .notActive: return L10n.tr("No active simulation session.")
        case .operationCancelled: return L10n.tr("Connection preparation cancelled.")
        case .operationTimedOut: return L10n.tr("The request timed out. The native operation is still finishing; location restoration is not confirmed.")
        case .operationBusy: return L10n.tr("Wait for the previous native operation to finish before trying again.")
        case .serviceUnreachable: return L10n.tr("RemotePairing is not reachable. Check the tunnel device IP, port and local network permission.")
        case .localNetworkDenied: return L10n.tr("Allow Local Network access for Locus in Settings, then check the connection again.")
        }
    }
}

/// The session depends on this boundary so delayed writes, validation failures,
/// and restoration responses can be supplied deterministically in tests.
@MainActor
protocol LocationTransport {
    var isStopPending: Bool { get }
    var isDraining: Bool { get }
    func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError>
    func clear(pairingPath: String?, deviceIP: String?) async -> Result<Void, LocationEngineError>
    func validateConnection(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError>
    func cancelPendingPreparation()
}
